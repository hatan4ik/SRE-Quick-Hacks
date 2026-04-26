# Terraform — Assessment Q&A

---

## MULTIPLE CHOICE (1 question)

### Q1. What is the correct order of Terraform workflow commands?

- A) `validate → init → plan → apply`
- B) `init → validate → plan → apply`
- C) `plan → init → apply → destroy`
- D) `init → plan → apply → validate`

**Answer: B**
`init` downloads providers/modules → `validate` checks syntax → `plan` shows diff → `apply` executes.

**Trap:** `validate` requires `init` to have run first (providers must be installed). You cannot validate before init.

---

## OPEN QUESTIONS (7 questions)

---

### Q2. What is Terraform state, and why is it important?

**Answer:**

Terraform state (`terraform.tfstate`) is a JSON file that maps real-world infrastructure to your configuration. It serves three purposes:

1. **Mapping** — links resource addresses (e.g. `aws_instance.web`) to real resource IDs (e.g. `i-0abc123`).
2. **Performance** — caches resource attributes so Terraform doesn't query every API on every plan.
3. **Dependency tracking** — records metadata needed to compute correct destroy order.

Without state, Terraform cannot determine what already exists and would try to create everything from scratch on every `apply`.

**Remote state** (S3 + DynamoDB, Terraform Cloud) is required in teams to:
- Share state across engineers
- Enable state locking (prevent concurrent applies corrupting state)
- Store state off local disk

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

**DynamoDB locking:** Terraform writes a `LockID` item before apply and deletes it after. Concurrent apply attempts block until the lock is released.

**Best practices:**
- Never edit state manually — use `terraform state mv`, `terraform state rm`
- Enable S3 versioning on the state bucket (rollback on corruption)
- Restrict state bucket access via IAM — state contains sensitive values in plaintext

---

### Q3. Explain Terraform modules. How do you call a module and pass variables to it?

**Answer:**

A module is a **reusable, self-contained collection of Terraform resources** in a directory. Every Terraform config is technically a module (the "root" module).

**Why use them:** DRY, encapsulation, versioning, testability.

**Module structure:**
```
modules/vpc/
  main.tf        # resources
  variables.tf   # input declarations
  outputs.tf     # output values
```

**Calling a module:**
```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"   # Terraform Registry
  version = "~> 5.0"                           # pin — never use without version

  # Input variables
  name       = "prod-vpc"
  cidr       = "10.0.0.0/16"
  azs        = ["us-east-1a", "us-east-1b"]
  environment = var.environment
}
```

**Accessing module outputs:**
```hcl
resource "aws_instance" "app" {
  subnet_id = module.vpc.private_subnet_ids[0]
}
```

**Key rules:**
- After adding/changing a module source, run `terraform init` again.
- Modules cannot access parent variables directly — everything must be passed explicitly.
- Use `version` constraints with registry modules; omitting version is a production risk.

---

### Q4. What is the difference between `count` and `for_each`? When would you use each?

**Answer:**

Both create multiple instances of a resource, but they differ in how instances are tracked in state.

**`count`** — integer-based, instances addressed by index `[0]`, `[1]`, …
```hcl
resource "aws_instance" "web" {
  count         = 3
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t3.micro"
  tags = { Name = "web-${count.index}" }
}
# reference: aws_instance.web[0].id
```

**Problem with `count`:** removing an element from the middle renumbers all subsequent indices → Terraform proposes destroy/recreate of wrong resources.

**`for_each`** — map or set-based, instances addressed by stable key `["key"]`
```hcl
variable "instances" {
  default = {
    web  = "t3.micro"
    api  = "t3.small"
    jobs = "t3.medium"
  }
}

resource "aws_instance" "app" {
  for_each      = var.instances
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = each.value
  tags = { Name = each.key }
}
# reference: aws_instance.app["web"].id
```

**Decision table:**
| Scenario | Use |
|---|---|
| N identical copies | `count` |
| Named, distinct resources from a map/set | `for_each` |
| Removing a middle element without side effects | `for_each` |
| Simple toggle (0 or 1) | `count` |
| IAM users, subnets, security group rules | `for_each` |

---

### Q5. What are Terraform workspaces and what are their limitations?

**Answer:**

Workspaces allow multiple **state files** within the same backend configuration, enabling environment separation without duplicating config files.

```bash
terraform workspace new staging
terraform workspace select production
terraform workspace list
```

Inside config, use `terraform.workspace`:
```hcl
locals {
  instance_type = terraform.workspace == "production" ? "t3.large" : "t3.micro"
}

resource "aws_s3_bucket" "data" {
  bucket = "myapp-${terraform.workspace}-data"
}
```

**Limitations — when NOT to use workspaces:**
1. All workspaces share the same backend config and provider credentials — no strong isolation.
2. A misconfigured destroy can affect the wrong environment.
3. Not suitable for truly isolated environments (different AWS accounts) — use **separate root modules** with separate state backends.
4. Poor discoverability — easy to forget which workspace is active.

**Best practice:** Workspaces for lightweight dev/staging differences; separate state backends + root modules for production isolation.

---

### Q6. Explain `lifecycle` meta-arguments. What does each argument do?

**Answer:**

`lifecycle` controls how Terraform handles resource replacement and updates.

```hcl
resource "aws_db_instance" "main" {
  identifier     = "prod-db"
  engine         = "mysql"
  instance_class = "db.t3.medium"

  lifecycle {
    prevent_destroy       = true           # 1
    create_before_destroy = true           # 2
    ignore_changes        = [password, tags["last_updated"]]  # 3
    replace_triggered_by  = [aws_subnet.main]                 # 4
  }
}
```

| Argument | Effect |
|---|---|
| `prevent_destroy` | Causes `terraform destroy` (or any plan that would destroy this resource) to **error out**. Protects prod databases, S3 buckets. |
| `create_before_destroy` | Creates replacement first, then destroys old. Default is destroy-then-create. Essential for zero-downtime (LB target groups, certs). |
| `ignore_changes` | Ignores drift on listed attributes. Use when an external system (auto-scaler, secrets rotation) owns those fields. `ignore_changes = all` is a last resort. |
| `replace_triggered_by` | Forces replacement of this resource when a referenced resource or attribute changes. |

**Trap:** `ignore_changes` can hide real security drift. Use narrowly.

---

### Q7. How do you import an existing AWS resource into Terraform? Walk through the full workflow.

**Answer:**

`terraform import` pulls an existing real resource into Terraform state without recreating it.

**Scenario:** Import an existing S3 bucket `my-legacy-bucket`.

**Step 1 — Write the config**
```hcl
resource "aws_s3_bucket" "legacy" {
  bucket = "my-legacy-bucket"
}
```

**Step 2 — Run import**
```bash
terraform import aws_s3_bucket.legacy my-legacy-bucket
#               ^resource address^     ^real resource ID^
```
Terraform calls the AWS API, fetches the bucket, writes its attributes into state.

**Step 3 — Reconcile config with state**
```bash
terraform plan
```
Review the diff. Update `main.tf` to match the real resource until plan shows **"No changes."**

**Step 4 — Commit** state and config to version control.

**Terraform 1.5+ — declarative `import` block:**
```hcl
import {
  to = aws_s3_bucket.legacy
  id = "my-legacy-bucket"
}
```
Run `terraform plan` to preview, `terraform apply` to complete. Use `terraform generate-config-to=generated.tf` to auto-generate HCL.

**Common import ID formats:**
| Resource | ID format |
|---|---|
| `aws_instance` | `i-1234567890abcdef0` |
| `aws_s3_bucket` | `bucket-name` |
| `aws_security_group` | `sg-12345678` |
| `aws_iam_role` | `role-name` |
| `aws_route53_record` | `ZONEID_name_TYPE` |

**Renamed resource block → use `moved` block (not import):**
```hcl
moved {
  from = aws_security_group.old_name
  to   = aws_security_group.web
}
```

---

### Q8. How do you manage secrets in Terraform? What are the risks?

**Answer:**

**Risks:**
- Secrets in `.tf` files get committed to git
- Secrets in state file are stored **in plaintext** by default — even `sensitive = true` variables land in state
- `terraform plan` output may expose sensitive values in CI logs

**Best practices:**

**1. Mark variables as sensitive (redacts CLI output, does NOT protect state):**
```hcl
variable "db_password" {
  type      = string
  sensitive = true
}
```

**2. Use environment variables — never hardcode:**
```bash
export TF_VAR_db_password="<value-from-vault>"
```

**3. Read from AWS Secrets Manager / SSM at plan time:**
```hcl
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "prod/db/password"
}
# Use: data.aws_secretsmanager_secret_version.db.secret_string
```

**4. Encrypt remote state:**
- S3 backend: `encrypt = true` + KMS key
- Terraform Cloud: encrypts by default

**5. Restrict state access:**
- S3 bucket policy: only CI role + break-glass role
- Never commit `terraform.tfvars` with real secrets — add to `.gitignore`

**6. Use provider-native secret references** where possible (e.g. RDS password from Secrets Manager ARN) so the secret value never passes through Terraform state.

---

### Q9. What is a `data` source? Provide real-world examples.

**Answer:**

A data source reads information from **existing infrastructure** (not managed by the current config) and makes it available in resource definitions. It performs a **read-only** API call during `plan`.

```hcl
# Fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.al2023.id
  instance_type = "t3.micro"
}
```

**Other common examples:**
```hcl
# Look up an existing VPC by tag
data "aws_vpc" "prod" {
  tags = { Environment = "prod" }
}

# Look up Route 53 zone
data "aws_route53_zone" "main" {
  name = "example.com."
}

# Read SSM Parameter Store secret
data "aws_ssm_parameter" "db_password" {
  name            = "/myapp/prod/db_password"
  with_decryption = true
}

# Read remote state outputs from another Terraform root module
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "company-tf-state"
    key    = "prod/network/terraform.tfstate"
    region = "us-east-1"
  }
}
# Use: data.terraform_remote_state.network.outputs.vpc_id
```

---

## Cheat Sheet

```bash
terraform init                          # download providers/modules
terraform fmt -recursive                # format all .tf files
terraform validate                      # syntax + schema check
terraform plan -out=tfplan              # preview, save plan
terraform apply tfplan                  # apply saved plan
terraform destroy                       # destroy all resources
terraform state list                    # list resources in state
terraform state show aws_instance.app   # show state for one resource
terraform state mv old_addr new_addr    # rename resource in state
terraform state rm aws_instance.app     # remove from state (no destroy)
terraform apply -replace=aws_instance.app  # force recreate
terraform import aws_s3_bucket.x name   # import existing resource
terraform workspace list/new/select     # manage workspaces
terraform output                        # show root outputs
```

**Key files:**
| File | Purpose |
|---|---|
| `main.tf` | Resources |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output values |
| `versions.tf` | `required_providers` + `required_version` |
| `terraform.tfvars` | Variable values (never commit secrets) |
| `.terraform.lock.hcl` | Provider version lock — **always commit this** |
