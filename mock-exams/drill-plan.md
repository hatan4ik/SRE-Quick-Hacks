# Drill Plan

## Day-Before Review

Spend 2 hours maximum. Do not try to learn every edge case.

1. Terraform state/backends/import/modules: 30 minutes.
2. Dockerfile writing from memory: 20 minutes.
3. Kubernetes troubleshooting scenarios: 45 minutes.
4. AWS networking/IAM/high availability: 25 minutes.

---

## Fast Recall Prompts + Answers

---

**1. Terraform plan shows destroy/create after a rename. What do you do?**

Use a `moved` block or `terraform state mv` to map the old address to the new one, then run `plan` to confirm no replacement is proposed.

```hcl
moved {
  from = aws_security_group.old_name
  to   = aws_security_group.web
}
```

---

**2. Terraform state contains secrets. How do you reduce risk?**

- Mark variables `sensitive = true` (redacts CLI output — does NOT protect state)
- Encrypt state at rest: S3 backend with `encrypt = true` + KMS key
- Restrict state bucket access via IAM — only CI role + break-glass role
- Never commit `terraform.tfvars` with real values
- Prefer data sources that read secret references (Secrets Manager ARN) so the value never flows through state

---

**3. Docker container cannot reach `localhost:5432`. Why?**

`localhost` inside a container refers to the container itself, not the host and not another container. In Docker Compose, use the service name instead: `postgres:5432`. Each container has its own network namespace.

---

**4. Docker image is huge. What changes reduce it?**

- Use a multi-stage build — compile in a builder stage, copy only the artifact to a slim runtime stage
- Use `alpine` or `distroless` as the runtime base image
- Install only production dependencies (`npm ci --omit=dev`, `pip install --no-cache-dir`)
- Add a `.dockerignore` to exclude `node_modules`, `.git`, test files, build outputs
- Combine `RUN` commands to avoid intermediate layers with cached package indexes

---

**5. Pod is Pending. What are five causes?**

1. Insufficient CPU or memory on any node to satisfy `requests`
2. Node selector or affinity rules that no node satisfies
3. Taint on all nodes with no matching toleration on the Pod
4. PersistentVolumeClaim cannot bind (no matching PV, wrong StorageClass)
5. Namespace resource quota exceeded

Diagnose with: `kubectl describe pod <name>` → look at the `Events` section at the bottom.

---

**6. Pod is CrashLoopBackOff. What commands do you run?**

```bash
# 1. Logs from the last crashed container instance
kubectl logs <pod> --previous -n <ns>

# 2. Events, probe failures, image issues, exit codes
kubectl describe pod <pod> -n <ns>

# 3. Check the Deployment config (bad CMD, missing env, wrong image)
kubectl get deploy <name> -o yaml -n <ns>
```

Common causes: app exits on startup, missing env var or secret, bad `CMD`/`ENTRYPOINT`, liveness probe killing the app before it's ready (fix: add `startupProbe`), permission denied on mounted volume.

---

**7. Service has no endpoints. What do you check?**

```bash
kubectl get endpoints <service> -n <ns>   # empty = selector mismatch or pods not Ready
kubectl get pods -l app=<label> -n <ns>   # are pods Running and Ready?
```

Checklist:
- Service `spec.selector` must exactly match Pod `metadata.labels`
- Pods must pass their `readinessProbe` to appear in endpoints
- `targetPort` must match the port the app actually listens on
- App must bind to `0.0.0.0`, not `127.0.0.1`
- NetworkPolicy may be blocking traffic

---

**8. Readiness vs liveness?**

| | Readiness | Liveness |
|---|---|---|
| Failure action | Remove Pod from Service endpoints (no restart) | Restart the container |
| Use case | App not ready to serve (warming up, DB not connected) | App is stuck/deadlocked and needs a restart |
| External deps | ✅ Safe to check (DB, cache) | ❌ Never check — if DB is down, you don't want all pods restarting |

`startupProbe` — disables both liveness and readiness until it passes. Use for slow-starting apps to prevent premature restarts.

---

**9. Security group vs NACL?**

| | Security Group | NACL |
|---|---|---|
| State | **Stateful** — return traffic automatically allowed | **Stateless** — must explicitly allow both inbound AND outbound |
| Applies to | EC2 instance / ENI level | Subnet level |
| Rules | Allow only (no explicit deny) | Allow AND Deny |
| Rule evaluation | All rules evaluated | Numbered order — lowest number wins |

Security groups are the primary control. NACLs are coarser subnet-level guardrails.

---

**10. Public vs private subnet?**

| | Public Subnet | Private Subnet |
|---|---|---|
| Route table | `0.0.0.0/0 → Internet Gateway` | `0.0.0.0/0 → NAT Gateway` |
| Inbound from internet | ✅ (if SG allows) | ❌ |
| Outbound to internet | ✅ directly | ✅ via NAT Gateway |
| Typical resources | ALB, NAT Gateway, bastion | App servers, databases, EKS nodes |

NAT Gateway itself must live in a **public** subnet and has an Elastic IP.

---

**11. ALB target unhealthy. What do you check?**

1. **Health check path/port** — does the app expose the exact path the ALB is checking? (e.g. `/healthz` returning 200)
2. **Security group** — does the ALB's SG have outbound to the target? Does the target's SG allow inbound from the ALB SG on the target port?
3. **App listening** — is the app actually running and bound to `0.0.0.0` on the target port?
4. **Target group port** — does it match the port the app listens on?
5. **App logs** — is the health check request hitting the app and returning a non-200?
6. **Thresholds** — are `HealthyThresholdCount` / `UnhealthyThresholdCount` / `Timeout` values realistic for your app's startup time?

---

**12. EC2 app needs S3 access. What is the secure pattern?**

Attach an **IAM Role** to the EC2 instance via an **instance profile**. The role has a least-privilege policy scoped to the specific bucket and actions needed.

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::my-bucket/*"
}
```

The EC2 instance retrieves temporary credentials automatically via IMDS (`169.254.169.254`). No long-lived access keys to rotate, leak, or commit to git.

**Never:** hardcode keys in env vars, user data, AMI, or application config.

---

## SRE Lead Answer Pattern

For open questions, answer in this order:

1. State the likely failure mode.
2. Name the first commands/signals you would inspect.
3. Explain immediate mitigation or rollback.
4. Explain permanent fix.
5. Mention safety: blast radius, observability, ownership, and review.

**Example — A rollout caused 5xx errors. What do you do?**

- Confirm impact with ALB/app metrics and logs.
- Compare error spike to deployment timeline.
- Stop rollout or roll back immediately if impact is active.
- Inspect health checks, target group, app logs, dependency latency, resource saturation.
- Fix root cause, add regression coverage/alerting, document incident timeline.

---

## Things Not To Do In The Real Assessment

- Do not paste memorized answers that do not address the exact question asked.
- Do not overcomplicate: clear first principles score better than vague buzzwords.
- Do not skip the "why" — examiners want reasoning, not just the answer.
