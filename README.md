# Priority Software — SRE Lead Assessment Prep

90-minute test: Terraform (1 MCQ + 7 open) · Docker (1 coding) · Kubernetes (9 MCQ + 2 open) · AWS (7 MCQ)

---

## Files

| File | What's inside |
|---|---|
| [terraform/terraform_qa.md](terraform/terraform_qa.md) | Full Q&A: state, backend, modules, count/for_each, workspaces, lifecycle, import, data sources, secrets |
| [docker/docker_qa.md](docker/docker_qa.md) | Full coding answer: multi-stage Node.js + Python + Go Dockerfiles, layer cache, CMD/ENTRYPOINT, ARG/ENV traps |
| [kubernetes/kubernetes_qa.md](kubernetes/kubernetes_qa.md) | Full Q&A: all 9 MCQ + 2 open, probes, RBAC YAML, requests/limits/QoS, HPA, NetworkPolicy, troubleshooting |
| [aws/aws_qa.md](aws/aws_qa.md) | Full Q&A: all 7 MCQ, VPC/NAT, IAM eval order, ALB vs NLB, RDS, Secrets Manager, ECS Task Role, EKS/IRSA |
| [mock-exams/mock_exam.md](mock-exams/mock_exam.md) | Full 90-min timed simulation — all questions, no answers visible until you scroll |
| [mock-exams/mock-90-minute.md](mock-exams/mock-90-minute.md) | Alternate mock with different question angles + full answer key |
| [mock-exams/drill-plan.md](mock-exams/drill-plan.md) | Day-before drill: fast-recall prompts + SRE lead answer pattern |
| [labs/docker-coding/Dockerfile.sample](labs/docker-coding/Dockerfile.sample) | Runnable Python Dockerfile with healthcheck |
| [labs/docker-coding/docker-compose.yml](labs/docker-coding/docker-compose.yml) | Compose with Postgres healthcheck dependency |
| [labs/kubernetes-manifests/app.yaml](labs/kubernetes-manifests/app.yaml) | Production Deployment + Service + PDB + HPA manifest |

---

## Last-Minute One-Liners

**Terraform**
- State = JSON map of config → real infra. Remote = S3 + DynamoDB lock. Never edit manually.
- `count` uses index → removing middle element causes wrong destroy. `for_each` uses stable key → safe.
- `lifecycle.prevent_destroy` = protects prod DB. `create_before_destroy` = zero-downtime replacement.
- `terraform import` = adds existing resource to state. You must write the HCL first. Run `plan` after to verify no diff.
- `moved {}` block = rename a resource in state without destroy/recreate.
- `.terraform.lock.hcl` = provider version lock. Always commit it.

**Docker**
- Multi-stage: build stage compiles, runtime stage copies only artifacts → no devDeps, no source, tiny image.
- `COPY package*.json ./` then `RUN npm ci` then `COPY . .` — deps layer cached until lockfile changes.
- `COPY` always over `ADD`. `ADD` from URLs bypasses cache and is unpredictable.
- Non-root: `addgroup -S appgroup && adduser -S appuser -G appgroup` then `USER appuser`.
- `dumb-init` as PID 1 → forwards SIGTERM to app correctly. Node as PID 1 does not handle signals well.
- `ENV` persists into container. `ARG` is build-time only. Never put secrets in either.

**Kubernetes**
- `livenessProbe` fail → container restarts. `readinessProbe` fail → removed from Service endpoints (no restart).
- `startupProbe` → disables liveness/readiness during slow startup. Prevents premature restarts.
- Memory limit exceeded → OOMKilled. CPU limit exceeded → throttled (not killed).
- `requests == limits` → Guaranteed QoS (last evicted). No requests/limits → BestEffort (first evicted).
- RBAC: `Role` (namespaced) + `RoleBinding` = namespace-scoped access. `ClusterRole` + `ClusterRoleBinding` = cluster-wide.
- `ClusterRole` + `RoleBinding` = reusable role definition, namespace-scoped binding. Common pattern.
- DaemonSet = one pod per node. StatefulSet = stable hostname + PVC per pod. HPA needs metrics-server + requests set.
- Service selector must match Pod labels exactly. Check with `kubectl get endpoints <svc>`.

**AWS**
- Explicit Deny > Explicit Allow > Default Deny. No exceptions. Ever.
- IAM Role on EC2 via instance profile = temporary credentials via IMDS. Never hardcode keys.
- ALB = Layer 7, path/host routing, Lambda targets, WAF. NLB = Layer 4, static IP, ultra-low latency.
- Security Group = stateful, ENI-level, allow-only. NACL = stateless, subnet-level, allow + deny, numbered order.
- Public subnet = route table has `0.0.0.0/0 → IGW`. Private subnet = `0.0.0.0/0 → NAT GW`.
- RDS Multi-AZ = HA/failover (synchronous standby). Read Replicas = read scaling (asynchronous).
- Secrets Manager = auto-rotation, RDS integration. Parameter Store = cheaper, no auto-rotation.
- ECS Task Role = app permissions. Task Execution Role = agent permissions (pull image, write logs).
- IRSA = IAM Roles for Service Accounts (EKS equivalent of ECS Task Role, uses OIDC federation).
