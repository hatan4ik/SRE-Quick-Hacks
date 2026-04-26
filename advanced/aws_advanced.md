# AWS — FAANG SRE Lead Level

These questions test architecture judgment, failure-mode thinking, and cost/reliability trade-offs at scale.

---

## Q1. Design a disaster recovery strategy for a production web application. Define RTO/RPO and map them to AWS patterns.

**Answer:**

**Terminology first:**
- **RTO** (Recovery Time Objective): How long can the business be down? (Time to restore service)
- **RPO** (Recovery Point Objective): How much data loss is acceptable? (Time since last backup)

**Four DR patterns, cost vs complexity:**

### Pattern 1: Backup & Restore (RTO: hours, RPO: hours)
```
Active region: us-east-1
  ↓ nightly
S3 backups + RDS snapshots (us-west-2 cross-region copy)

Recovery: provision new infra from Terraform + restore backup
Cost: very low (storage only)
Use case: dev/staging, or businesses with low criticality
```

### Pattern 2: Pilot Light (RTO: 15-30 min, RPO: minutes)
```
us-east-1 (active):          us-west-2 (pilot light):
  ECS services (running)        RDS replica (running)
  ALB + ASG (running)           ECS services (0 tasks)
  RDS primary                   ALB (exists, no targets)

RDS: async cross-region replica (RPO = replication lag, typically < 1 min)
Failover: promote RDS replica, scale ECS tasks from 0 → N, update Route53
Cost: medium (replica + cold infra)
```

### Pattern 3: Warm Standby (RTO: 1-5 min, RPO: seconds)
```
us-east-1 (active):          us-west-2 (warm standby):
  ECS 10 tasks                  ECS 2 tasks (minimal)
  RDS primary                   RDS replica → Aurora Global DB
  ALB → Route53 weighted        ALB → Route53 health-check failover

Route53 health check: if primary fails → auto-failover DNS in 60-120s
Aurora Global: RPO < 1 second, failover < 1 minute (managed)
Cost: high (running duplicate infra at reduced scale)
```

### Pattern 4: Multi-Site Active-Active (RTO: 0, RPO: 0 for reads)
```
us-east-1 ←→ us-west-2 (both active, split traffic)
Route53 latency routing: users go to nearest region
DynamoDB Global Tables: multi-master, replicates in <1s
Aurora Global: write in primary, read from any region
S3 Cross-Region Replication

Cost: very high (full duplicate infra)
Use case: financial systems, global consumer apps
```

**Tooling:**
```bash
# Aurora Global DB failover
aws rds failover-global-cluster \
  --global-cluster-identifier my-global-cluster \
  --target-db-cluster-identifier arn:aws:rds:us-west-2:...

# Route53 health check failover record
aws route53 change-resource-record-sets ...
# Or use Route53 Application Recovery Controller for controlled failover
```

**Lead-level add:** DR is not set-and-forget. Run a **game day** quarterly:
1. Manually trigger failover in staging
2. Measure actual RTO (usually 2-3x your estimate)
3. Document gaps → fix them before the real incident

---

## Q2. Explain cross-account IAM. How do you give your CI/CD pipeline in account A the ability to deploy to account B?

**Answer — this is a lead-level pattern used in every enterprise AWS setup.**

**Why separate accounts?** AWS Organizations account isolation is the strongest security boundary in AWS. Prod in its own account means a compromised dev credential cannot affect prod.

**The mechanism: AssumeRole + trust policy**

**Step 1 — In account B (prod), create the deployment role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCIFromAccountA",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/github-actions-role"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "my-unique-external-id-12345"
        }
      }
    }
  ]
}
```

**Step 2 — In account A (CI), grant the CI role permission to assume the prod role:**
```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::222222222222:role/prod-deployment-role"
}
```

**Step 3 — In CI/CD pipeline:**
```bash
# GitHub Actions: assume prod role
aws sts assume-role \
  --role-arn arn:aws:iam::222222222222:role/prod-deployment-role \
  --role-session-name github-deploy-$(date +%s) \
  --external-id my-unique-external-id-12345 \
  | jq -r '.Credentials | "AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nAWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nAWS_SESSION_TOKEN=\(.SessionToken)"' \
  >> $GITHUB_ENV
```

**Better with GitHub OIDC (no long-lived keys at all):**
```yaml
# GitHub Actions OIDC — account A CI
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::111111111111:role/github-actions-role
    aws-region: us-east-1

# Then immediately assume-role into account B
- run: |
    CREDS=$(aws sts assume-role \
      --role-arn arn:aws:iam::222222222222:role/prod-deployment-role \
      --role-session-name deploy)
    echo "AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)" >> $GITHUB_ENV
    # ...
```

**Account structure at scale (AWS Organizations):**
```
Root (management account — billing only, no workloads)
├── Security OU
│   ├── Log Archive account (CloudTrail, Config centralized logs)
│   └── Security Tooling account (GuardDuty, Security Hub)
├── Infrastructure OU
│   └── Shared Services account (ECR, Artifactory, DNS)
├── Workloads OU
│   ├── Dev account
│   ├── Staging account
│   └── Prod account
```

---

## Q3. VPC Peering vs Transit Gateway vs PrivateLink — when do you use each?

**Answer:**

**VPC Peering:**
```
VPC-A ←→ VPC-B   (direct, non-transitive)
```
- One-to-one connection, no IP overlap allowed
- Non-transitive: A↔B, B↔C does NOT allow A↔C (must also peer A↔C)
- No bandwidth limit beyond VPC limits
- Same or cross-account, same or cross-region
- **Use when:** simple two-VPC connectivity, low operational overhead needed, IPs don't overlap

**Transit Gateway (TGW):**
```
VPC-A ──┐
VPC-B ──┤→ Transit Gateway → on-prem (via VPN/DX)
VPC-C ──┘
```
- Hub-and-spoke, transitive routing
- Attach up to 5000 VPCs, supports VPN and Direct Connect
- Route tables on TGW control what can talk to what (production isolation)
- **Use when:** 3+ VPCs, hub-and-spoke connectivity, on-prem hybrid, multi-account

**PrivateLink:**
```
Consumer VPC → Interface Endpoint (ENI) → PrivateLink → Service VPC (NLB)
```
- One-directional: consumer calls producer's service
- No route table changes, no IP overlap concern
- Traffic never leaves AWS backbone
- Used for AWS services (S3, DynamoDB, STS endpoints), also for exposing your own service
- **Use when:** exposing a service to other VPCs/accounts without giving network access, SaaS patterns, AWS service endpoints in private subnets

**Decision tree:**
```
Two VPCs, no overlap → Peering (cheapest)
Many VPCs or on-prem → Transit Gateway
Expose one service only → PrivateLink
```

---

## Q4. A Lambda function is timing out intermittently at 14 seconds (timeout is 15s). How do you diagnose and fix it?

**Answer — Lambda troubleshooting is a common lead-level scenario.**

**Immediate diagnosis:**
```python
# In the Lambda code: structured logging to CloudWatch
import time
import logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    start = time.time()
    logger.info(f"remaining_ms={context.get_remaining_time_in_millis()}")
    
    # log before each I/O call
    t0 = time.time()
    result = db.query(...)
    logger.info(f"db_query_ms={int((time.time()-t0)*1000)}")
```

**CloudWatch Logs Insights query to find slow invocations:**
```sql
fields @timestamp, @duration, @memorySize, @maxMemoryUsed
| filter @duration > 10000
| sort @timestamp desc
| limit 50
```

**Common causes and fixes:**

**1. Cold start + heavy initialization**
```python
# BAD: connection inside handler = new connection every invocation
def handler(event, context):
    conn = psycopg2.connect(...)  # cold path every time

# GOOD: connection outside handler = reused across warm invocations
conn = psycopg2.connect(os.environ['DB_URL'])  # initialized once on cold start

def handler(event, context):
    # reuses conn
```

**2. Database connection exhaustion (RDS)**
```
Lambda scales to 1000+ concurrent invocations → 1000+ DB connections → RDS max_connections exceeded → Lambda waits for connection → timeout
```
**Fix:** RDS Proxy absorbs connection spikes, pools connections, Lambda connects to proxy:
```hcl
resource "aws_db_proxy" "main" {
  name     = "lambda-proxy"
  role_arn = aws_iam_role.proxy.arn
  vpc_subnet_ids = var.private_subnet_ids
  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db.arn
    iam_auth    = "REQUIRED"
  }
}
```

**3. VPC cold start (ENI provisioning)**
- Lambda in VPC takes 1-10s extra on cold start to provision the ENI
- Modern Lambda uses pre-provisioned ENIs (fixed in 2020), but confirm you're on a recent runtime
- Use Provisioned Concurrency for latency-sensitive functions

**4. Downstream API timeout not set**
```python
# BAD: no timeout → waits until Lambda times out
response = requests.get("https://slow-api.example.com/data")

# GOOD: fail fast, let Lambda retry or use DLQ
response = requests.get("https://slow-api.example.com/data", timeout=(3, 10))
# (connect_timeout, read_timeout)
```

**5. Memory too low → CPU throttling**
Lambda CPU is proportional to memory. A memory-bound function that's CPU-limited will be slow.
```bash
# Check if increasing memory reduced duration (and cost stays same or drops)
aws lambda update-function-configuration --function-name my-fn --memory-size 1024
# Run load test, compare duration * memory_used (cost) vs previous
```

---

## Q5. You're about to be paged because your AWS bill doubled this month. Walk through your cost investigation.

**Answer — an SRE lead is responsible for cost as much as reliability.**

**Step 1: Identify the spike — AWS Cost Explorer**
```bash
# CLI version
aws ce get-cost-and-usage \
  --time-period Start=2026-01-01,End=2026-01-31 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```
Identify: which service, which account, which region.

**Step 2: Drill into the culprit**

**EC2 / EKS nodes:**
```bash
# Are you running more instances than expected?
aws ec2 describe-instances --filters Name=instance-state-name,Values=running \
  --query 'Reservations[*].Instances[*].[InstanceId,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
  --output table

# Any forgotten test clusters?
aws eks list-clusters
```

**Data transfer (often hidden cost):**
- Cross-AZ data transfer: $0.01/GB each way (hidden cost in microservices)
- NAT Gateway: $0.045/GB processed (Lambda, ECS → internet through NAT)
- Fix: VPC Endpoints for S3/DynamoDB eliminate NAT Gateway data transfer cost

**S3 storage / requests:**
```bash
aws s3api list-buckets --query 'Buckets[*].Name' --output text | \
  xargs -I{} aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 --metric-name BucketSizeBytes \
    --dimensions Name=BucketName,Value={} Name=StorageType,Value=StandardStorage \
    --start-time 2026-01-01 --end-time 2026-01-31 \
    --period 2592000 --statistics Average
```

**Step 3: Immediate cost reduction levers**

| Action | Savings |
|--------|---------|
| Right-size over-provisioned EC2 | 20-40% |
| Reserved Instances / Savings Plans | 30-60% for stable workloads |
| Spot Instances for non-critical | 60-90% |
| S3 Intelligent-Tiering for aging data | 40-60% on storage |
| Delete unattached EBS volumes / snapshots | Quick win |
| VPC Endpoints for S3/DDB | Eliminates NAT GW data transfer |
| CloudFront in front of S3/ALB | Reduces origin data transfer |
| Clean up unused Elastic IPs | $3.65/month each when unattached |

**Long-term: tagging + cost allocation**
```hcl
resource "aws_instance" "web" {
  tags = {
    Environment = "prod"
    Team        = "platform"
    CostCenter  = "engineering-infra"
    Service     = "api-gateway"
  }
}
```
Enable **Cost Allocation Tags** in Billing → each team sees their own spend → accountability.

---

## Q6. How do you harden an AWS account from day one? (SRE lead joining a new team)

**Answer — this is an SRE lead "what would you do first" question.**

**Week 1 checklist:**

```
IAM:
  ✅ Enable MFA on root account and all IAM users
  ✅ Delete root account access keys (there should be none)
  ✅ Enable IAM Access Analyzer — finds externally accessible resources
  ✅ Enable AWS Organizations + SCP: deny regions you don't use
  ✅ Check for users with AdministratorAccess — should be < 3 people

Logging & Visibility:
  ✅ CloudTrail: enable in ALL regions, send to central S3 (log archive account)
  ✅ AWS Config: enable, record all resource types, send to central bucket
  ✅ GuardDuty: enable in all regions, send findings to Security Hub
  ✅ S3 server access logging on state buckets and sensitive buckets

Network:
  ✅ Default VPC: delete or lock down (sg with no rules)
  ✅ S3 Block Public Access: enable at account level
  ✅ No security group with 0.0.0.0/0 on port 22 or 3389

Preventive controls (SCPs):
  ✅ Deny IAM actions from non-CI roles in prod account
  ✅ Deny disabling CloudTrail
  ✅ Deny GuardDuty and Config opt-out
  ✅ Deny regions outside your usage (reduces attack surface)
```

**Sample SCP — deny disabling guardrails:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyDisablingGuardDuty",
      "Effect": "Deny",
      "Action": [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "config:DeleteConfigRule",
        "config:StopConfigurationRecorder"
      ],
      "Resource": "*"
    }
  ]
}
```
