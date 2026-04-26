# AWS — Assessment Q&A

---

## MULTIPLE CHOICE (7 questions)

---

### MCQ1. Your EC2 instance in a private subnet needs to download packages from the internet without being directly reachable from the internet. What do you need?

- A) Internet Gateway attached to the private subnet
- B) NAT Gateway in a public subnet, with a route in the private subnet route table pointing to it
- C) VPC Peering connection
- D) VPN Gateway

**Answer: B**

Traffic flow: `Private EC2 → NAT Gateway (public subnet) → Internet Gateway → Internet`

Key points:
- **NAT Gateway** must live in a **public subnet** (has an Elastic IP)
- **Private subnet route table** needs: `0.0.0.0/0 → nat-xxxxxxxx`
- **Public subnet route table** needs: `0.0.0.0/0 → igw-xxxxxxxx`
- NAT Gateway is managed, HA, auto-scaling (vs. NAT Instance = self-managed EC2, single point of failure)

---

### MCQ2. Which IAM policy type takes precedence when there is a conflict between an allow and a deny?

- A) Allow always wins
- B) Explicit Deny always wins over Explicit Allow
- C) The most recently applied policy wins
- D) Resource-based policies win over identity-based policies

**Answer: B**

AWS IAM evaluation order:
1. **Explicit Deny** → immediately deny, regardless of any Allow
2. SCP (Service Control Policy) — org-level guardrails
3. Resource-based policy (e.g. S3 bucket policy)
4. Identity-based policy (attached to user/role)
5. Session policy
6. **Default Deny** — if no explicit Allow, deny

"Deny beats Allow" is the foundational IAM rule. No exceptions.

---

### MCQ3. You need a load balancer that operates at Layer 7, supports path-based and host-based routing, and can forward to Lambda functions. Which service?

- A) Classic Load Balancer (CLB)
- B) Network Load Balancer (NLB)
- C) Application Load Balancer (ALB)
- D) Gateway Load Balancer (GWLB)

**Answer: C**

| LB Type | Layer | Use Case |
|---|---|---|
| CLB | 4+7 | Legacy — avoid for new workloads |
| NLB | 4 (TCP/UDP/TLS) | Ultra-low latency, static IP, preserve client IP, PrivateLink |
| ALB | 7 (HTTP/HTTPS/gRPC) | Microservices, path/host routing, Lambda, WebSocket, WAF |
| GWLB | 3 | Third-party network appliances (firewalls, IDS/IPS) |

ALB features: path routing (`/api` → A, `/static` → B), host routing, sticky sessions, HTTP/2, redirect rules, Lambda targets, ECS/EKS integration.

---

### MCQ4. An S3 bucket policy explicitly DENIES `s3:GetObject` to all principals. An IAM user has an identity policy that explicitly ALLOWS `s3:GetObject` on this bucket. What happens?

- A) Access is granted because identity policy allows it
- B) Access is denied because the bucket policy explicit deny wins
- C) Access is granted because resource-based policies override identity policies
- D) Access depends on the order the policies were applied

**Answer: B**

Explicit Deny in **any** policy (identity, resource, SCP) always wins. The bucket policy's `Deny` overrides the IAM `Allow`.

```json
{
  "Effect": "Deny",
  "Principal": "*",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*"
}
```

`Principal: "*"` with `Deny` blocks everyone including the bucket owner (unless using account-level S3 Block Public Access).

---

### MCQ5. Which AWS service provides a fully managed relational database with automatic failover, multi-AZ, and read replicas for read scaling?

- A) DynamoDB
- B) ElastiCache
- C) RDS
- D) Redshift

**Answer: C** — RDS (Relational Database Service)

Key RDS concepts:
- **Multi-AZ** — synchronous standby in another AZ, automatic failover (<60s). Used for **HA**, NOT read scaling.
- **Read Replicas** — asynchronous replication, up to 5 per instance (15 for Aurora). Used for **read scaling** and cross-region DR.
- **Aurora** — AWS-optimized MySQL/PostgreSQL, 6-way replication across 3 AZs, up to 15 read replicas, Aurora Serverless for variable workloads.
- **RDS Proxy** — connection pooling, reduces DB connections from Lambda/ECS.

---

### MCQ6. You need to store application secrets (DB passwords, API keys) and automatically rotate them. Which service?

- A) S3 with server-side encryption
- B) Systems Manager Parameter Store (SecureString)
- C) AWS Secrets Manager
- D) KMS directly

**Answer: C** — AWS Secrets Manager

| Feature | Parameter Store | Secrets Manager |
|---|---|---|
| Cost | Free (standard) | $0.40/secret/month |
| Automatic rotation | ❌ manual | ✅ built-in Lambda rotation |
| RDS native integration | ❌ | ✅ |
| Cross-account | Limited | ✅ |
| Max value size | 8 KB | 64 KB |
| Audit via CloudTrail | ✅ | ✅ |

Use Secrets Manager when: rotation is required, RDS credentials, cross-account sharing. Use Parameter Store for non-secret config, hierarchical configs, or cost sensitivity.

---

### MCQ7. An ECS task on Fargate needs to call `s3:PutObject` on a specific S3 bucket. How do you grant minimum required permissions?

- A) Embed AWS access keys in the container's environment variables
- B) Attach an IAM role to the ECS task using a Task Role, with a policy granting `s3:PutObject` on the bucket
- C) Attach the policy to the ECS service IAM role
- D) Assign the IAM role to the Fargate cluster

**Answer: B** — ECS Task Role

| Role | Purpose |
|---|---|
| **Task Role** | Permissions for the application code running INSIDE the container (S3, DDB, SQS, etc.) |
| **Task Execution Role** | Permissions for the ECS/Fargate AGENT (pull ECR image, write CloudWatch logs, read Secrets Manager) |

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::my-bucket/*"
  }]
}
```

The task role uses IMDS to vend temporary credentials to the container — **never hard-code access keys**.

---

## Cheat Sheet

### IAM Policy evaluation

```
1. Explicit Deny  → DENY immediately (no exceptions)
2. SCP            → must Allow
3. Resource policy → check
4. Identity policy → check
5. Default         → DENY (implicit)
```

### VPC architecture

```
Region
└── VPC (10.0.0.0/16)
    ├── Public Subnet AZ-a (10.0.1.0/24)  → route: 0.0.0.0/0 → IGW
    ├── Public Subnet AZ-b (10.0.2.0/24)  → route: 0.0.0.0/0 → IGW
    ├── Private Subnet AZ-a (10.0.11.0/24) → route: 0.0.0.0/0 → NAT-GW
    └── Private Subnet AZ-b (10.0.12.0/24) → route: 0.0.0.0/0 → NAT-GW
```

| | Security Group | NACL |
|---|---|---|
| State | **Stateful** (return traffic auto-allowed) | **Stateless** (must allow both directions) |
| Applies to | EC2 instance / ENI level | Subnet level |
| Rules | Allow only | Allow AND Deny |
| Evaluation | All rules evaluated | Numbered order (lowest first) |

- **VPC Peering** — connect two VPCs, non-transitive (A↔B, B↔C ≠ A↔C)
- **Transit Gateway** — hub-and-spoke, transitive routing between VPCs and on-prem

### ALB vs NLB

| | ALB | NLB |
|---|---|---|
| Layer | 7 (HTTP/HTTPS/gRPC) | 4 (TCP/UDP/TLS) |
| Routing | Path, host, header, query string | IP + port |
| Static IP | ❌ (use Global Accelerator) | ✅ |
| WebSocket | ✅ | ✅ |
| Lambda targets | ✅ | ❌ |
| Preserve client IP | Via X-Forwarded-For header | ✅ natively |
| Use case | Web apps, microservices, WAF | High perf, static IP, PrivateLink |

### S3 storage classes (cost: high → low)

| Class | Retrieval | Use case |
|---|---|---|
| Standard | Immediate | Frequent access |
| Standard-IA | Immediate | Infrequent, rapid access needed |
| One Zone-IA | Immediate | Infrequent, non-critical |
| Glacier Instant | Milliseconds | Archives, accessed ~quarterly |
| Glacier Flexible | Minutes–hours | Archives, flexible retrieval |
| Glacier Deep Archive | ~12 hours | Long-term, rarely accessed |
| Intelligent-Tiering | Automatic | Unknown/changing access patterns |

### EKS key points

- Managed control plane (AWS manages etcd, API server, HA across AZs)
- Worker nodes: Managed Node Groups, Self-Managed, Fargate
- **IRSA (IAM Roles for Service Accounts)** — binds IAM role to k8s ServiceAccount via OIDC federation (equivalent of ECS Task Role for EKS)
- `aws-auth` ConfigMap (or Access Entries) — maps IAM roles/users to k8s RBAC
- AWS Load Balancer Controller — creates ALB/NLB from Ingress/Service resources
- EKS Add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver

### Route 53

| Record | Use |
|---|---|
| A | Hostname → IPv4 |
| AAAA | Hostname → IPv6 |
| CNAME | Hostname → hostname (NOT valid at zone apex) |
| Alias | Hostname → AWS resource (ALB, CloudFront, S3) — works at apex, free queries |

Routing policies: Simple, Weighted, Latency, Geolocation, Failover, Multi-Value

### IAM best practices

1. **Explicit Deny > Explicit Allow > Default Deny**
2. **Roles > Users** — use IAM roles for services, not long-lived access keys
3. **Least privilege** — grant only what's needed, scope to specific resources
4. **MFA** on all human users, especially root
5. **SCP** — set maximum permissions for AWS Org accounts
6. **Permission boundaries** — limit max permissions a role can grant

### Common IAM policy structure

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::my-bucket",
      "arn:aws:s3:::my-bucket/*"
    ],
    "Condition": {
      "StringEquals": {"aws:RequestedRegion": "us-east-1"}
    }
  }]
}
```
