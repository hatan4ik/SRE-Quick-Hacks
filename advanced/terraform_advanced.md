# Terraform — FAANG SRE Lead Level

These questions distinguish a senior engineer who uses Terraform from a lead who owns it at scale.

---

## Q1. Your Terraform state file is corrupted mid-apply. Production is partially deployed. Walk through recovery.

**Answer — this is a war story question. Structure: diagnose → contain → recover → prevent.**

**Immediate: determine actual state of infra**
```bash
# 1. Check what exists in AWS right now (ground truth)
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod"

# 2. Inspect what Terraform thinks exists
terraform show

# 3. Check S3 versioning for last known-good state
aws s3api list-object-versions \
  --bucket my-tf-state \
  --prefix prod/terraform.tfstate \
  --query 'Versions[*].[VersionId,LastModified]' \
  --output table
```

**Recovery options (safest to most destructive):**

**Option A — Restore previous state version (preferred if partially written)**
```bash
# Pull the last good version from S3
aws s3api get-object \
  --bucket my-tf-state \
  --key prod/terraform.tfstate \
  --version-id <GOOD_VERSION_ID> \
  terraform.tfstate.restore

# Push it back (forces it to be current)
terraform state push terraform.tfstate.restore
```

**Option B — Re-import resources not in state**
```bash
terraform state list        # see what state knows about
# For each resource that exists in AWS but not in state:
terraform import aws_instance.web i-0abc1234
```

**Option C — `terraform refresh` + reconcile**
```bash
terraform refresh           # sync state to actual infra
terraform plan              # review what changed
```

**Prevention checklist:**
| Control | Implementation |
|---------|---------------|
| S3 versioning | `versioning { enabled = true }` on state bucket |
| DynamoDB lock | Always use; prevents concurrent writes that cause corruption |
| Never edit state manually | Use `terraform state mv/rm/import` |
| Periodic state backup | Script to copy state to a cold backup bucket daily |
| Never `Ctrl-C` during apply | If you must kill it, let the operation finish and check manually |

---

## Q2. You have 80 microservices each with their own Terraform config. How do you structure this without copy/paste explosion?

**Answer — module architecture at scale.**

**Anti-pattern: copy/paste service directories**
```
services/
  auth/main.tf      # copy of payments/main.tf
  payments/main.tf  # copy of auth/main.tf
  # 78 more copies...
```
Any change to the pattern requires 80 PRs.

**Pattern: shared module library + service configs**
```
infra/
  modules/
    ecs-service/        # reusable ECS service module
      main.tf
      variables.tf
      outputs.tf
    rds-postgres/
    redis-cluster/
  services/
    auth/
      main.tf           # 15 lines: calls modules with service-specific values
      variables.tf
    payments/
      main.tf           # same 15 lines, different vars
  envs/
    dev/
    staging/
    prod/
```

**Service module call (15 lines per service):**
```hcl
module "auth_service" {
  source  = "../../modules/ecs-service"
  version = "~> 2.0"

  name            = "auth"
  environment     = var.environment
  image           = "123456789.dkr.ecr.us-east-1.amazonaws.com/auth:${var.image_tag}"
  cpu             = 256
  memory          = 512
  desired_count   = 2
  container_port  = 8080
  health_check_path = "/healthz"
}
```

**Module versioning strategy:**
- Modules live in a separate repo, tagged with semver (`v2.1.0`)
- Use `version = "~> 2.0"` constraint — accepts `2.x` but not `3.x`
- Breaking changes → bump major, services upgrade on their own schedule
- CHANGELOG.md in the module repo lists migration steps

**Terragrunt for DRY backend config:**
```hcl
# terragrunt.hcl (root)
remote_state {
  backend = "s3"
  config = {
    bucket = "company-tf-state"
    key    = "${path_relative_to_include()}/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-locks"
  }
}
```
Each service inherits the backend config, only `key` changes.

---

## Q3. How do you prevent a Terraform apply in one service from accidentally destroying resources owned by another?

**Answer — blast radius isolation.**

**Root cause:** Terraform only knows about resources in its own state. A misconfigured `data` source, wrong `terraform destroy`, or `count = 0` accidentally removes something shared.

**Defense layers:**

**1. State isolation** — each service, each environment has its own state file. Never share state.
```
s3://tf-state/services/auth/prod/terraform.tfstate
s3://tf-state/services/payments/prod/terraform.tfstate
```

**2. `prevent_destroy` on all critical resources**
```hcl
resource "aws_rds_cluster" "main" {
  lifecycle {
    prevent_destroy = true
  }
}
```

**3. Scoped IAM role per service** — the CI role for `auth` can only touch `auth`-tagged resources:
```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "StringNotEquals": {
      "aws:ResourceTag/Service": "auth"
    }
  }
}
```

**4. OPA / Checkov policy in CI** — block plans that destroy production resources:
```rego
# opa policy: deny if plan destroys any aws_rds_cluster in prod
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_rds_cluster"
  resource.change.actions[_] == "delete"
  msg := sprintf("Denied: plan destroys RDS cluster %v", [resource.address])
}
```

**5. Required apply approval** — never auto-apply production. Plan is reviewed by a second engineer before apply runs.

---

## Q4. Explain Terraform's `precondition` and `postcondition` blocks. When do they outperform `variable validation`?

**Answer:**

Introduced in Terraform 1.2. Allow inline assertions on resource/data behavior, not just input values.

**`variable` validation** — runs before any API calls, only checks input value:
```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev","staging","prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}
```

**`precondition`** — runs at plan time, can reference data sources and other resources:
```hcl
data "aws_ami" "app" {
  most_recent = true
  owners      = ["self"]
  filter { name = "name"; values = ["myapp-*"] }
}

resource "aws_instance" "app" {
  ami = data.aws_ami.app.id

  lifecycle {
    precondition {
      # Fail plan if the AMI is older than 30 days
      condition     = timecmp(data.aws_ami.app.creation_date, timeadd(timestamp(), "-720h")) > 0
      error_message = "AMI is older than 30 days. Rebuild it first."
    }
  }
}
```

**`postcondition`** — runs after apply, verifies the outcome:
```hcl
resource "aws_lb" "api" {
  ...
  lifecycle {
    postcondition {
      condition     = self.dns_name != ""
      error_message = "ALB was created but has no DNS name — check subnet config."
    }
  }
}
```

**When preconditions beat variable validation:**
- You need to check a value that comes from a data source (not just user input)
- You want to assert cross-resource invariants
- You want clear error messages at plan time instead of cryptic API errors at apply time

---

## Q5. How do you handle secrets in Terraform without ever writing them to state?

**Answer — this is a lead-level security question. State is not a secrets store.**

**Problem:** Any `sensitive = true` variable is still stored in `terraform.tfstate` in plaintext (base64 in some cases). State must be treated as a secret itself.

**Strategy 1 — Don't put secrets in Terraform at all**
Use `aws_secretsmanager_secret_version` data source at runtime, not at deploy time:
```hcl
# Terraform creates the secret skeleton, but NOT the value
resource "aws_secretsmanager_secret" "db_password" {
  name = "/myapp/prod/db-password"
}

# The value is set by a separate rotation Lambda or manually
# The app reads it at runtime via AWS SDK — never in state
```

**Strategy 2 — External secret stores with Vault provider**
```hcl
provider "vault" {
  address = "https://vault.internal"
}

data "vault_generic_secret" "db_creds" {
  path = "secret/prod/db"
}

resource "aws_db_instance" "main" {
  password = data.vault_generic_secret.db_creds.data["password"]
  # This value IS in state — mitigate with encrypted state + Vault dynamic secrets
}
```

**Strategy 3 — Vault dynamic secrets (best for DB)**
```hcl
data "vault_database_secret_backend_creds" "db" {
  backend = "database"
  role    = "myapp-role"
}
# Returns short-lived credentials — if state is leaked, creds are already expired
```

**Strategy 4 — SOPS encrypted tfvars**
```bash
# Encrypt vars file with AWS KMS
sops --kms arn:aws:kms:us-east-1:123:key/abc --encrypt secrets.tfvars > secrets.tfvars.enc
# Commit secrets.tfvars.enc — never secrets.tfvars
# CI decrypts at runtime
sops --decrypt secrets.tfvars.enc > secrets.tfvars
terraform apply -var-file=secrets.tfvars
```

**Minimum baseline regardless of strategy:**
- State bucket uses SSE-KMS (not SSE-S3)
- State bucket is NOT public
- State access is audited via CloudTrail
- `sensitive = true` on all secret-touching outputs and variables

---

## Q6. What is Terraform drift and how do you detect and handle it systematically in a team?

**Answer:**

**Drift** = divergence between Terraform state (what Terraform thinks exists) and actual infrastructure. Caused by:
- Manual console changes
- External automation (autoscalers, lambdas modifying tags)
- Other teams' Terraform or scripts touching shared resources
- Expired/rotated credentials changing secrets

**Detection — `terraform plan` is your drift report:**
```bash
# In CI — run plan on a schedule (e.g. nightly), alert on non-empty plans
terraform plan -detailed-exitcode
# Exit code 0 = no changes, 1 = error, 2 = changes detected
```

**Systematic drift pipeline:**
```yaml
# GitHub Actions — nightly drift detection
on:
  schedule:
    - cron: '0 6 * * *'   # 6am UTC daily

jobs:
  drift-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: terraform init
      - run: terraform plan -detailed-exitcode -out=drift.tfplan
        id: plan
      - if: steps.plan.outputs.exitcode == '2'
        uses: slackapi/slack-github-action@v1
        with:
          payload: '{"text":"⚠️ Drift detected in prod — review plan"}'
```

**Response playbook:**
| Type of drift | Response |
|---------------|----------|
| Tag change by another team | Add `ignore_changes = [tags]` or align |
| Security group rule added manually | Roll back manual change OR codify it |
| Autoscaler changed `desired_count` | Add `ignore_changes = [desired_count]` |
| Resource deleted manually | `terraform state rm` then re-import or recreate |
| Unrecognized resource in console | `terraform import` to bring under management |

**Team process:**
- No console changes to IaC-managed resources (enforced by `aws:via-console` deny SCP or just a team agreement)
- All changes go through PRs with plan artifacts
- Drift alerts go to a `#infra-drift` Slack channel, on-call owns resolution within 24h
