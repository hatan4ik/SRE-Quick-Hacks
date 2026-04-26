# Mock 90-Minute SRE/DevOps Assessment

Set a 90-minute timer. Answer everything before reading the answers. No notes.

---

## Section 1: Terraform — 25 min

### Terraform MCQ 1

You manage a list of IAM users with `count`. A new user is inserted at the beginning of the list. What is the main risk?

A. Terraform will ignore all users
B. Terraform may propose replacing or renaming resources because indexes changed
C. Terraform will automatically switch to `for_each`
D. Terraform will disable state locking

---

### Terraform Open 1

Your team uses local Terraform state and two engineers accidentally apply changes at the same time. Explain the failure mode and propose a better production setup.

---

### Terraform Open 2

An S3 bucket exists in AWS but is not managed by Terraform. You need Terraform to manage it without recreating it. What steps do you take?

---

### Terraform Open 3

You changed the name of a Terraform resource block and now the plan shows destroy/create. How do you preserve the existing resource?

---

### Terraform Open 4

How would you design Terraform code for dev, staging, and production while minimizing copy/paste?

---

### Terraform Open 5

What are the risks of using `ignore_changes` broadly?

---

### Terraform Open 6

Explain provider version pinning and why `.terraform.lock.hcl` should be committed.

---

### Terraform Open 7

What does a good Terraform CI/CD workflow look like for production?

---

## Section 2: Docker Coding — 15 min

You are given a Python API with:
- `requirements.txt`
- `app/main.py`
- Listens on port `8080`
- Start command: `python -m app.main`
- Health endpoint: `/healthz`

Write a Dockerfile that:
- Uses a slim Python base image
- Installs dependencies efficiently (layer cache)
- Runs as a non-root user
- Exposes port 8080
- Uses exec-form CMD
- Avoids pip cache

Bonus: include a HEALTHCHECK.

---

## Section 3: Kubernetes — 30 min

### Kubernetes MCQ 1

A Pod is `Pending`. Which command is most useful first?

A. `kubectl logs pod`
B. `kubectl describe pod`
C. `kubectl delete namespace`
D. `kubectl rollout undo`

---

### Kubernetes MCQ 2

What does a readiness probe control?

A. Whether the container should be restarted
B. Whether the Pod receives Service traffic
C. Whether an image can be pulled
D. Whether the node joins the cluster

---

### Kubernetes MCQ 3

Your Service has no endpoints. What is a likely cause?

A. Service selector does not match Pod labels
B. Too many ConfigMaps
C. CPU limit is too low
D. `kubectl` is outdated

---

### Kubernetes MCQ 4

What does `kubectl logs --previous` help debug?

A. Previous kubeconfig context
B. Previous crashed container instance
C. Previous Helm chart version only
D. Previous Service selector

---

### Kubernetes MCQ 5

What happens when a container exceeds its memory limit?

A. It can be OOMKilled
B. It is only throttled
C. It is automatically moved live to another node
D. The namespace is deleted

---

### Kubernetes MCQ 6

Which object is best for one Pod per node?

A. Deployment
B. DaemonSet
C. Job
D. Ingress

---

### Kubernetes MCQ 7

What is a PDB used for?

A. Prevent all application crashes
B. Limit voluntary disruptions below availability requirements
C. Store passwords
D. Route HTTP paths

---

### Kubernetes MCQ 8

Which object is commonly used for HTTP path routing into Services?

A. ConfigMap
B. Ingress
C. PVC
D. Secret

---

### Kubernetes MCQ 9

What do CPU requests affect directly?

A. Scheduling and HPA CPU utilization baseline
B. Docker image size
C. DNS record TTL
D. Secret encryption

---

### Kubernetes Open 1

A new Deployment rollout is stuck. Pods exist but are not Ready. Walk through your debugging process.

---

### Kubernetes Open 2

Explain a safe production rollout strategy for a stateless service.

---

## Section 4: AWS — 15 min

### AWS MCQ 1

What is the difference between a security group and a NACL?

A. Security groups are stateless; NACLs are stateful
B. Security groups are stateful and ENI-level; NACLs are stateless and subnet-level
C. Both are only IAM features
D. NACLs replace route tables

---

### AWS MCQ 2

What allows private subnet instances to initiate outbound internet access?

A. Internet Gateway directly attached to instance
B. NAT Gateway with route table entry
C. S3 bucket policy
D. Route 53 private hosted zone only

---

### AWS MCQ 3

What is the safest way for an EC2 instance to access S3?

A. Hardcoded access keys
B. IAM role through instance profile
C. Root account access key
D. Public bucket policy

---

### AWS MCQ 4

What does RDS Multi-AZ mainly provide?

A. High availability/failover
B. Unlimited read scaling
C. Object storage
D. DNS hosting

---

### AWS MCQ 5

Which S3 setting helps recover from accidental overwrite?

A. Versioning
B. Public ACL
C. Website hosting
D. Transfer acceleration only

---

### AWS MCQ 6

An ALB target is unhealthy. What should you check?

A. Health check path/port, app listening, security groups, target logs
B. Only IAM password policy
C. Only S3 lifecycle policy
D. Only Route 53 TTL

---

### AWS MCQ 7

Which IAM statement overrides an allow?

A. Explicit deny
B. Tag value
C. Oldest policy
D. Region setting

---

---

# Answer Key

---

## Terraform Answers

### Terraform MCQ 1 — Answer: B

`count` indexes are positional. Inserting a user at index 0 shifts every subsequent index. Terraform sees `aws_iam_user.user[0]` as a different resource than before and may propose destroy/recreate of the wrong users. Use `for_each` with a `toset()` of names — each user is keyed by name, not position, so insertions and removals are safe.

```hcl
# Safe pattern
resource "aws_iam_user" "user" {
  for_each = toset(var.users)
  name     = each.value
}
```

---

### Terraform Open 1

**Failure mode:** Local state has no locking. Two concurrent `terraform apply` runs both read the same state, compute their own plans, and write back — the second write overwrites the first. The result is state that no longer reflects real infrastructure, leading to phantom resources, missed destroys, or duplicate creates.

**Production setup:**

```hcl
terraform {
  backend "s3" {
    bucket         = "company-tf-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

- DynamoDB table provides atomic locking — only one apply runs at a time
- S3 versioning enables rollback if state is corrupted
- Restrict bucket access via IAM — only the CI role can read/write state
- Plans run in CI, require peer review, apply only from the pipeline with scoped credentials

---

### Terraform Open 2

**Step 1 — Write the resource block:**
```hcl
resource "aws_s3_bucket" "legacy" {
  bucket = "my-existing-bucket"
}
```

**Step 2 — Import the real resource into state:**
```bash
terraform import aws_s3_bucket.legacy my-existing-bucket
```

**Step 3 — Reconcile config with state:**
```bash
terraform plan
```
Review the diff. Update `main.tf` to match the real resource (tags, versioning, ACL, etc.) until plan shows **"No changes."**

**Step 4 — Commit** both the config and the updated state.

**Terraform 1.5+ alternative — declarative import block:**
```hcl
import {
  to = aws_s3_bucket.legacy
  id = "my-existing-bucket"
}
```
Run `terraform plan` to preview, `terraform apply` to complete. Use `terraform generate-config-to=generated.tf` to auto-generate the HCL skeleton.

---

### Terraform Open 3

Use a `moved` block (Terraform 1.1+) to tell Terraform the old address maps to the new one — no destroy/recreate:

```hcl
moved {
  from = aws_security_group.old_name
  to   = aws_security_group.web
}
```

Or use `terraform state mv` for an immediate state-only rename:
```bash
terraform state mv aws_security_group.old_name aws_security_group.web
```

Then run `terraform plan` to confirm the plan shows **"No changes."** The `moved` block is preferred because it is version-controlled and self-documenting.

---

### Terraform Open 4

**Pattern: reusable modules + separate root modules per environment**

```
infra/
  modules/
    vpc/          # reusable module
    rds/
    ecs-service/
  envs/
    dev/
      main.tf     # calls modules, dev-specific values
      terraform.tfvars
    staging/
      main.tf
    prod/
      main.tf
```

- Each `envs/<env>/` has its own state backend key — full isolation
- Modules expose typed variables with validation; environments pass values
- CI gates: dev applies freely, staging requires review, prod requires approval + plan artifact
- Never share state between prod and non-prod

**What NOT to do:** workspaces for prod isolation — they share the same backend config and credentials, making a misfire possible.

---

### Terraform Open 5

`ignore_changes` tells Terraform to never update a field after initial creation, even if the real value drifts from config.

**Risks of broad use:**
- Hides real security drift — e.g. someone widens a security group rule and Terraform never reverts it
- Hides accidental manual changes that should be codified
- Makes `terraform plan` output misleading — "No changes" when real drift exists
- `ignore_changes = all` effectively removes Terraform's ability to manage the resource

**Correct use:** narrow, specific fields owned by an external system:
```hcl
ignore_changes = [tags["last_modified_by"], desired_count]
# desired_count managed by auto-scaler, not Terraform
```

---

### Terraform Open 6

**Provider version pinning** in `versions.tf`:
```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # allows 5.x, blocks 6.x
    }
  }
}
```

**`.terraform.lock.hcl`** records the exact provider version and checksums selected by `terraform init`. It ensures every engineer and every CI run installs the identical provider binary.

**Why commit it:**
- Without it, `terraform init` may silently upgrade a provider and introduce breaking changes
- Checksums protect against supply-chain attacks (tampered provider binaries)
- Upgrade intentionally with `terraform init -upgrade`, review the diff, then commit the updated lockfile

---

### Terraform Open 7

**Production Terraform CI/CD workflow:**

```
PR opened
  → terraform fmt -check          (fail if unformatted)
  → terraform validate            (syntax + schema)
  → tfsec / checkov               (static security scan)
  → terraform plan -out=tfplan    (plan against real state)
  → publish plan as PR artifact   (reviewers see exact changes)

PR approved + merged
  → terraform apply tfplan        (apply the reviewed plan, not a new one)
  → notify Slack / PagerDuty
  → tag state version in S3

Guards:
  - Remote locked state (S3 + DynamoDB)
  - Scoped CI IAM role (least privilege per environment)
  - Separate pipelines per environment (dev auto-applies, prod requires manual approval)
  - Never apply from a local laptop in production
```

---

## Docker Answer

```dockerfile
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Non-root user
RUN addgroup --system app && adduser --system --ingroup app app

# Dependency layer — cached until requirements.txt changes
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Application code
COPY app ./app

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"

CMD ["python", "-m", "app.main"]
```

**Why each decision matters:**
- `python:3.12-slim` — pinned version, no `latest`; slim removes most build tools
- `COPY requirements.txt` before `COPY app` — deps layer is cached until lockfile changes, not on every source edit
- `--no-cache-dir` — pip does not write a local cache into the image layer
- `adduser --system` — no password, no home dir, no shell; limits blast radius
- `USER app` before `CMD` — process runs as non-root
- Exec-form `CMD ["python", "-m", "app.main"]` — process receives SIGTERM directly (not via shell)
- `HEALTHCHECK` — Docker and orchestrators can detect an unhealthy container

---

## Kubernetes Answers

### MCQ answers

| # | Answer | Why |
|---|---|---|
| 1 | **B** | `kubectl describe pod` shows scheduling events, probe failures, image errors — the most information for a Pending pod |
| 2 | **B** | Readiness controls Service endpoint membership — failed readiness = no traffic, no restart |
| 3 | **A** | Service selector must exactly match Pod labels; mismatch = empty endpoints |
| 4 | **B** | `--previous` shows logs from the last terminated container instance — essential for CrashLoopBackOff |
| 5 | **A** | Exceeding memory limit → OOMKill. Exceeding CPU limit → throttled (not killed) |
| 6 | **B** | DaemonSet ensures exactly one Pod per node, including nodes added later |
| 7 | **B** | PDB limits voluntary disruptions (node drain, cluster upgrade) — does not protect against node failure |
| 8 | **B** | Ingress defines HTTP(S) routing rules to Services, implemented by an ingress controller |
| 9 | **A** | `requests` are used by the scheduler to place Pods AND by HPA to calculate CPU utilization percentage |

---

### Kubernetes Open 1 — Deployment rollout stuck, Pods not Ready

**Step-by-step debug process:**

```bash
# 1. Check overall rollout status
kubectl rollout status deployment/<name> -n <ns>

# 2. Compare old vs new ReplicaSets — how many pods are Ready in each?
kubectl get replicasets -n <ns> -l app=<label>

# 3. Describe the stuck Pod — look at Events at the bottom
kubectl describe pod <pod-name> -n <ns>

# 4. Check logs — is the app crashing or failing its readiness check?
kubectl logs <pod-name> -n <ns>
kubectl logs <pod-name> -n <ns> --previous   # if it's restarting

# 5. Check events across the namespace
kubectl get events --sort-by='.lastTimestamp' -n <ns>
```

**Common root causes and fixes:**

| Symptom in describe | Cause | Fix |
|---|---|---|
| `Readiness probe failed` | App not returning 200 on health path | Fix app, check port/path config |
| `Back-off pulling image` | Wrong image tag or missing pull secret | Fix image ref or add `imagePullSecret` |
| `Insufficient cpu/memory` | Node has no capacity for new pods | Scale cluster or reduce requests |
| `Error: secret not found` | Missing Secret or ConfigMap mount | Create the missing resource |
| `OOMKilled` | Memory limit too low | Increase memory limit |

**If production is impacted — roll back first, debug second:**
```bash
kubectl rollout undo deployment/<name> -n <ns>
```

---

### Kubernetes Open 2 — Safe production rollout for a stateless service

**Deployment strategy:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0   # never reduce below desired replica count
    maxSurge: 1         # create one extra pod before removing old ones
```

**Full checklist:**

1. **Readiness probe** — new Pods only receive traffic after passing readiness. Without this, rolling update sends traffic to Pods that aren't ready.

2. **PodDisruptionBudget** — prevents voluntary disruptions from taking too many Pods offline simultaneously:
```yaml
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-service
```

3. **Resource requests set** — HPA and scheduler need accurate requests to maintain capacity during the rollout.

4. **Monitor during rollout** — watch error rate, latency, and pod readiness in real time:
```bash
kubectl rollout status deployment/<name> -n <ns> --watch
```

5. **Fast rollback path** — if metrics degrade, roll back immediately:
```bash
kubectl rollout undo deployment/<name> -n <ns>
```

6. **Canary / progressive delivery** (bonus) — for high-risk changes, route 5–10% of traffic to the new version first using Argo Rollouts or a weighted Ingress rule before full rollout.

---

## AWS Answers

| # | Answer | Why |
|---|---|---|
| 1 | **B** | Security groups are stateful (return traffic auto-allowed) and ENI-level. NACLs are stateless (must allow both directions) and subnet-level. |
| 2 | **B** | NAT Gateway in a public subnet + route `0.0.0.0/0 → nat-xxx` in the private subnet route table. NAT Gateway itself needs `0.0.0.0/0 → IGW` in the public subnet. |
| 3 | **B** | IAM role via instance profile — temporary credentials via IMDS. No long-lived keys to rotate or leak. |
| 4 | **A** | Multi-AZ = synchronous standby in another AZ, automatic failover (<60s). It is NOT a read endpoint. Read Replicas = read scaling (asynchronous). |
| 5 | **A** | S3 Versioning keeps all previous versions of every object and uses delete markers, enabling recovery from overwrites and accidental deletes. |
| 6 | **A** | Check: health check path returns 200, correct port, app bound to `0.0.0.0`, security group allows ALB → target on target port, app logs for errors. |
| 7 | **A** | Explicit Deny always overrides any Allow, regardless of which policy it comes from (identity, resource, SCP). No exceptions. |
