# Mock 90-Minute SRE/DevOps Assessment

Set a 90-minute timer. Answer everything before reading the answers. No notes.

---

## Section 1: Terraform — 25 min

---

### Terraform MCQ 1

You manage a list of IAM users with `count`. A new user is inserted at the beginning of the list. What is the main risk?

A. Terraform will ignore all users
B. Terraform may propose replacing or renaming resources because indexes changed
C. Terraform will automatically switch to `for_each`
D. Terraform will disable state locking

**Answer: B**

`count` indexes are positional. Inserting a user at index 0 shifts every subsequent index. Terraform sees `aws_iam_user.user[0]` as a different resource and may propose destroy/recreate of the wrong users. Use `for_each` with `toset()` — each user is keyed by name, not position.

```hcl
resource "aws_iam_user" "user" {
  for_each = toset(var.users)
  name     = each.value
}
```

---

### Terraform Open 1

Your team uses local Terraform state and two engineers accidentally apply changes at the same time. Explain the failure mode and propose a better production setup.

**Answer:**

**Failure mode:** Local state has no locking. Two concurrent `terraform apply` runs both read the same state, compute their own plans, and write back — the second write overwrites the first. Result: state no longer reflects real infrastructure → phantom resources, missed destroys, or duplicate creates.

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

- DynamoDB provides atomic locking — only one apply runs at a time
- S3 versioning enables rollback if state is corrupted
- Restrict bucket access via IAM — only the CI role can read/write state
- Plans run in CI, require peer review, apply only from the pipeline with scoped credentials

---

### Terraform Open 2

An S3 bucket exists in AWS but is not managed by Terraform. You need Terraform to manage it without recreating it. What steps do you take?

**Answer:**

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
Update `main.tf` to match the real resource until plan shows **"No changes."**

**Step 4 — Commit** both config and updated state.

**Terraform 1.5+ alternative:**
```hcl
import {
  to = aws_s3_bucket.legacy
  id = "my-existing-bucket"
}
```
Run `terraform plan` to preview, `terraform apply` to complete. Use `terraform generate-config-to=generated.tf` to auto-generate the HCL skeleton.

---

### Terraform Open 3

You changed the name of a Terraform resource block and now the plan shows destroy/create. How do you preserve the existing resource?

**Answer:**

Use a `moved` block (Terraform 1.1+) — no destroy/recreate:

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

Then run `terraform plan` to confirm **"No changes."** The `moved` block is preferred — it is version-controlled and self-documenting.

---

### Terraform Open 4

How would you design Terraform code for dev, staging, and production while minimizing copy/paste?

**Answer:**

**Pattern: reusable modules + separate root modules per environment**

```
infra/
  modules/
    vpc/
    rds/
    ecs-service/
  envs/
    dev/
      main.tf          # calls modules with dev values
      terraform.tfvars
    staging/
      main.tf
    prod/
      main.tf
```

- Each `envs/<env>/` has its own state backend key — full isolation
- Modules expose typed variables with validation; environments pass values
- CI gates: dev auto-applies, staging requires review, prod requires approval + plan artifact
- Never share state between prod and non-prod

**What NOT to do:** workspaces for prod isolation — they share the same backend config and credentials, making a misfire possible.

---

### Terraform Open 5

What are the risks of using `ignore_changes` broadly?

**Answer:**

`ignore_changes` tells Terraform to never update a field after initial creation, even if the real value drifts from config.

**Risks:**
- Hides real security drift — e.g. someone widens a security group rule and Terraform never reverts it
- Hides accidental manual changes that should be codified
- Makes `terraform plan` misleading — "No changes" when real drift exists
- `ignore_changes = all` effectively removes Terraform's ability to manage the resource

**Correct use — narrow, specific fields owned by an external system:**
```hcl
lifecycle {
  ignore_changes = [tags["last_modified_by"], desired_count]
  # desired_count is managed by auto-scaler, not Terraform
}
```

---

### Terraform Open 6

Explain provider version pinning and why `.terraform.lock.hcl` should be committed.

**Answer:**

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

What does a good Terraform CI/CD workflow look like for production?

**Answer:**

```
PR opened
  → terraform fmt -check          (fail if unformatted)
  → terraform validate            (syntax + schema)
  → tfsec / checkov               (static security scan)
  → terraform plan -out=tfplan    (plan against real state)
  → publish plan as PR artifact   (reviewers see exact changes)

PR approved + merged
  → terraform apply tfplan        (apply the reviewed plan, not a fresh one)
  → notify Slack / PagerDuty
  → tag state version in S3

Guards:
  - Remote locked state (S3 + DynamoDB)
  - Scoped CI IAM role (least privilege per environment)
  - Separate pipelines per environment (dev auto-applies, prod requires manual approval)
  - Never apply from a local laptop in production
```

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

**Answer:**

```dockerfile
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN addgroup --system app && adduser --system --ingroup app app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=2)"

CMD ["python", "-m", "app.main"]
```

**Why each decision matters:**
- `python:3.12-slim` — pinned version, no `latest`; slim removes most build tools
- `COPY requirements.txt` before `COPY app` — deps layer cached until requirements change, not on every source edit
- `--no-cache-dir` — pip does not write a local cache into the image layer
- `adduser --system` — no password, no home dir, no shell; limits blast radius
- `USER app` before `CMD` — process runs as non-root
- Exec-form `CMD` — process receives SIGTERM directly, not via shell
- `HEALTHCHECK` — Docker and orchestrators can detect an unhealthy container

---

## Section 3: Kubernetes — 30 min

---

### Kubernetes MCQ 1

A Pod is `Pending`. Which command is most useful first?

A. `kubectl logs pod`
B. `kubectl describe pod`
C. `kubectl delete namespace`
D. `kubectl rollout undo`

**Answer: B**

`kubectl describe pod` shows scheduling events, probe failures, and image errors — the most information for a Pending pod. The `Events` section at the bottom shows exactly why the scheduler couldn't place it (insufficient resources, unsatisfied affinity, taint mismatch, PVC unbound).

---

### Kubernetes MCQ 2

What does a readiness probe control?

A. Whether the container should be restarted
B. Whether the Pod receives Service traffic
C. Whether an image can be pulled
D. Whether the node joins the cluster

**Answer: B**

Readiness probe failure → Pod removed from Service endpoints → no traffic sent to it. Pod stays running, no restart. Liveness probe failure → container restart. This distinction is critical for rolling deployments.

---

### Kubernetes MCQ 3

Your Service has no endpoints. What is a likely cause?

A. Service selector does not match Pod labels
B. Too many ConfigMaps
C. CPU limit is too low
D. `kubectl` is outdated

**Answer: A**

Service `spec.selector` must exactly match Pod `metadata.labels`. A single typo or missing label = empty endpoints. Diagnose with:
```bash
kubectl get endpoints <service> -n <ns>
kubectl get pods -l app=<label> -n <ns>
```

---

### Kubernetes MCQ 4

What does `kubectl logs --previous` help debug?

A. Previous kubeconfig context
B. Previous crashed container instance
C. Previous Helm chart version only
D. Previous Service selector

**Answer: B**

`--previous` shows logs from the last terminated container instance. Essential for `CrashLoopBackOff` — the current container may have just started, but `--previous` shows why the last one died.

---

### Kubernetes MCQ 5

What happens when a container exceeds its memory limit?

A. It can be OOMKilled
B. It is only throttled
C. It is automatically moved live to another node
D. The namespace is deleted

**Answer: A**

Exceeding memory limit → kernel OOMKills the container. Exceeding CPU limit → throttled (not killed). This is a key difference: memory is a hard limit, CPU is a soft cap.

---

### Kubernetes MCQ 6

Which object is best for one Pod per node?

A. Deployment
B. DaemonSet
C. Job
D. Ingress

**Answer: B**

DaemonSet ensures exactly one Pod per node, including nodes added later. Common uses: log collectors (Fluentd), monitoring agents (Datadog, Prometheus node-exporter), CNI plugins.

---

### Kubernetes MCQ 7

What is a PDB used for?

A. Prevent all application crashes
B. Limit voluntary disruptions below availability requirements
C. Store passwords
D. Route HTTP paths

**Answer: B**

PodDisruptionBudget limits voluntary disruptions (node drain, cluster upgrade) — Kubernetes will not evict Pods if doing so would violate the budget. It does NOT protect against involuntary disruptions (node failure).

```yaml
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-service
```

---

### Kubernetes MCQ 8

Which object is commonly used for HTTP path routing into Services?

A. ConfigMap
B. Ingress
C. PVC
D. Secret

**Answer: B**

Ingress defines HTTP(S) routing rules (path-based, host-based) to backend Services, implemented by an ingress controller (nginx, AWS ALB Controller, Traefik). A Service of type `LoadBalancer` creates an NLB on AWS, not an ALB.

---

### Kubernetes MCQ 9

What do CPU requests affect directly?

A. Scheduling and HPA CPU utilization baseline
B. Docker image size
C. DNS record TTL
D. Secret encryption

**Answer: A**

`requests.cpu` is used by the scheduler to find a node with enough capacity AND by HPA to calculate CPU utilization percentage. A Pod with no CPU requests cannot be meaningfully scaled by CPU-based HPA.

---

### Kubernetes Open 1

A new Deployment rollout is stuck. Pods exist but are not Ready. Walk through your debugging process.

**Answer:**

```bash
# 1. Overall rollout status
kubectl rollout status deployment/<name> -n <ns>

# 2. Compare old vs new ReplicaSets
kubectl get replicasets -n <ns> -l app=<label>

# 3. Describe the stuck Pod — read Events at the bottom
kubectl describe pod <pod-name> -n <ns>

# 4. Check app logs
kubectl logs <pod-name> -n <ns>
kubectl logs <pod-name> -n <ns> --previous   # if restarting

# 5. Namespace-wide events
kubectl get events --sort-by='.lastTimestamp' -n <ns>
```

**Common root causes:**

| Symptom in `describe` | Cause | Fix |
|---|---|---|
| `Readiness probe failed` | App not returning 200 on health path | Fix app or probe config |
| `Back-off pulling image` | Wrong image tag or missing pull secret | Fix image ref or add `imagePullSecret` |
| `Insufficient cpu/memory` | No node has capacity | Scale cluster or reduce requests |
| `secret not found` | Missing Secret or ConfigMap | Create the missing resource |
| `OOMKilled` | Memory limit too low | Increase memory limit |

**If production is impacted — roll back first, debug second:**
```bash
kubectl rollout undo deployment/<name> -n <ns>
```

---

### Kubernetes Open 2

Explain a safe production rollout strategy for a stateless service.

**Answer:**

**Rolling update config:**
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0   # never reduce below desired replica count
    maxSurge: 1         # create one extra pod before removing old ones
```

**Full checklist:**

1. **Readiness probe** — new Pods only receive traffic after passing. Without it, rolling update sends traffic to unready Pods.

2. **PodDisruptionBudget** — prevents voluntary disruptions from taking too many Pods offline:
```yaml
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: my-service
```

3. **Resource requests set** — HPA and scheduler need accurate requests to maintain capacity during rollout.

4. **Monitor during rollout:**
```bash
kubectl rollout status deployment/<name> -n <ns> --watch
```

5. **Fast rollback:**
```bash
kubectl rollout undo deployment/<name> -n <ns>
```

6. **Canary (bonus)** — route 5–10% of traffic to the new version first using Argo Rollouts or a weighted Ingress rule before full rollout.

---

## Section 4: AWS — 15 min

---

### AWS MCQ 1

What is the difference between a security group and a NACL?

A. Security groups are stateless; NACLs are stateful
B. Security groups are stateful and ENI-level; NACLs are stateless and subnet-level
C. Both are only IAM features
D. NACLs replace route tables

**Answer: B**

| | Security Group | NACL |
|---|---|---|
| State | Stateful — return traffic auto-allowed | Stateless — must allow both directions |
| Applies to | EC2 instance / ENI | Subnet |
| Rules | Allow only | Allow AND Deny |
| Evaluation | All rules | Numbered order, lowest first |

---

### AWS MCQ 2

What allows private subnet instances to initiate outbound internet access?

A. Internet Gateway directly attached to instance
B. NAT Gateway with route table entry
C. S3 bucket policy
D. Route 53 private hosted zone only

**Answer: B**

Traffic flow: `Private EC2 → NAT Gateway (public subnet) → IGW → Internet`

- NAT Gateway must live in a **public subnet** (has an Elastic IP)
- Private subnet route table: `0.0.0.0/0 → nat-xxxxxxxx`
- Public subnet route table: `0.0.0.0/0 → igw-xxxxxxxx`

---

### AWS MCQ 3

What is the safest way for an EC2 instance to access S3?

A. Hardcoded access keys
B. IAM role through instance profile
C. Root account access key
D. Public bucket policy

**Answer: B**

IAM role via instance profile → temporary credentials delivered via IMDS (`169.254.169.254`). No long-lived keys to rotate, leak, or accidentally commit to git. This is the AWS-recommended pattern for all EC2 workloads.

---

### AWS MCQ 4

What does RDS Multi-AZ mainly provide?

A. High availability/failover
B. Unlimited read scaling
C. Object storage
D. DNS hosting

**Answer: A**

Multi-AZ = synchronous standby replica in another AZ, automatic failover in under 60 seconds. It is **not** a read endpoint — the standby is passive. Read Replicas = asynchronous replication used for read scaling.

---

### AWS MCQ 5

Which S3 setting helps recover from accidental overwrite?

A. Versioning
B. Public ACL
C. Website hosting
D. Transfer acceleration only

**Answer: A**

S3 Versioning keeps all previous versions of every object and uses delete markers instead of permanent deletes. Enables recovery from overwrites and accidental deletes by restoring a previous version.

---

### AWS MCQ 6

An ALB target is unhealthy. What should you check?

A. Health check path/port, app listening, security groups, target logs
B. Only IAM password policy
C. Only S3 lifecycle policy
D. Only Route 53 TTL

**Answer: A**

Checklist:
1. Health check path returns HTTP 200 (check the exact path configured in the target group)
2. App is listening on `0.0.0.0` on the target port (not `127.0.0.1`)
3. Security group on the target allows inbound from the ALB security group on the target port
4. Target group port matches the port the app listens on
5. App logs for errors on the health check request

---

### AWS MCQ 7

Which IAM statement overrides an allow?

A. Explicit deny
B. Tag value
C. Oldest policy
D. Region setting

**Answer: A**

Explicit Deny always overrides any Allow, regardless of which policy it comes from — identity policy, resource policy, or SCP. The full evaluation order is: Explicit Deny → SCP → Resource policy → Identity policy → Default Deny. No exceptions.
