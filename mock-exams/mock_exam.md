# Mock Exam — 90-Minute Full Simulation

Set a timer. Answer everything before checking. No notes.

---

## TERRAFORM — 25 min (1 MCQ + 7 Open)

**MCQ-T1:** Correct order of Terraform workflow commands?
`A) validate→init→plan→apply  B) init→validate→plan→apply  C) plan→init→apply  D) init→plan→apply→validate`
> **C**... wait — **Answer: B**

**OQ-T1:** What is Terraform state? Why does it matter? What breaks without it?

**OQ-T2:** Write an S3 remote backend with DynamoDB locking. What does each field do?

**OQ-T3:** What are modules? Write a module call with `source`, `version`, and two input variables. How do you access module outputs?

**OQ-T4:** `count` vs `for_each` — what is the key difference? When does `count` cause destroy/recreate of the wrong resource?

**OQ-T5:** What are workspaces? Name two limitations that make them unsuitable for production isolation.

**OQ-T6:** Explain all four `lifecycle` arguments. Which one protects a production database from accidental deletion?

**OQ-T7:** Walk through the full `terraform import` workflow for an existing S3 bucket. What is the Terraform 1.5+ alternative?

---

## DOCKER — 15 min (1 Coding)

**CQ-D1:** Write a production Dockerfile for a Node.js/TypeScript app:
- Multi-stage build (deps / build / runtime stages)
- Non-root user
- `dumb-init` for PID 1 signal handling
- Health check on `/healthz`
- Port 3000

---

## KUBERNETES — 30 min (9 MCQ + 2 Open)

**MCQ-K1:** `CrashLoopBackOff` — first command?
`A) get pod -o yaml  B) logs --previous  C) describe pod  D) exec -it`
> **Answer: B**

**MCQ-K2:** Which probe removes a Pod from Service endpoints WITHOUT restarting it?
`A) liveness  B) startup  C) readiness  D) health`
> **Answer: C**

**MCQ-K3:** What does `resources.requests` do?
`A) max allowed usage  B) used by scheduler to place Pod  C) triggers OOMKill  D) sets Guaranteed QoS`
> **Answer: B**

**MCQ-K4:** 3-replica Deployment: creates 1 new Pod, waits for Ready, then kills 1 old. What config?
`A) Recreate  B) RollingUpdate maxSurge=1 maxUnavailable=0  C) RollingUpdate maxSurge=0 maxUnavailable=1  D) Blue/Green`
> **Answer: B**

**MCQ-K5:** Stable network identity + ordered startup + PVC per pod?
`A) Deployment  B) DaemonSet  C) StatefulSet  D) ReplicaSet`
> **Answer: C**

**MCQ-K6:** ClusterIP Service → accessible from internet via AWS ALB?
`A) NodePort  B) LoadBalancer  C) Ingress + AWS LB Controller  D) ExternalName`
> **Answer: C**

**MCQ-K7:** What does a PodDisruptionBudget protect against?
`A) CPU spikes  B) voluntary disruptions (node drain) reducing Pods below threshold  C) memory OOMKill  D) namespace quota`
> **Answer: B**

**MCQ-K8:** One Pod per node, including new nodes?
`A) Deployment replicas=100  B) StatefulSet  C) DaemonSet  D) CronJob`
> **Answer: C**

**MCQ-K9:** Grant ServiceAccount permissions in one namespace only?
`A) ClusterRole+ClusterRoleBinding  B) Role+RoleBinding  C) Role+ClusterRoleBinding  D) ServiceAccountPolicy`
> **Answer: B**

**OQ-K1:** Explain all three probe types (startup/liveness/readiness). What happens on failure for each? Why should liveness NOT check external dependencies?

**OQ-K2:** Explain RBAC. Write the full YAML (ServiceAccount + Role + RoleBinding) for read-only Pod access in the `production` namespace. Show how to verify with `kubectl auth can-i`.

---

## AWS — 15 min (7 MCQ)

**MCQ-A1:** Private EC2 needs outbound internet. What do you need?
`A) IGW on private subnet  B) NAT Gateway in public subnet + route  C) VPC Peering  D) VPN Gateway`
> **Answer: B**

**MCQ-A2:** IAM Allow vs Deny conflict — what wins?
`A) Allow  B) Explicit Deny always wins  C) Most recent policy  D) Resource policy wins`
> **Answer: B**

**MCQ-A3:** Layer 7, path-based routing, Lambda targets?
`A) CLB  B) NLB  C) ALB  D) GWLB`
> **Answer: C**

**MCQ-A4:** Bucket policy Denies `s3:GetObject` to `*`. IAM policy Allows it. Result?
`A) Granted — IAM wins  B) Denied — bucket Deny wins  C) Granted — resource policy wins  D) Depends on order`
> **Answer: B**

**MCQ-A5:** Managed RDS with automatic failover + read scaling?
`A) DynamoDB  B) ElastiCache  C) RDS  D) Redshift`
> **Answer: C** (Multi-AZ = HA/failover; Read Replicas = read scaling)

**MCQ-A6:** Store DB passwords with automatic rotation?
`A) S3+SSE  B) SSM Parameter Store  C) Secrets Manager  D) KMS directly`
> **Answer: C**

**MCQ-A7:** ECS Fargate task needs `s3:PutObject`. Correct approach?
`A) Env vars with keys  B) Task Role with scoped policy  C) Service IAM role  D) Cluster IAM role`
> **Answer: B**

---

## Score Tracker

| Section | Points | Score |
|---|---|---|
| Terraform MCQ | 1 | |
| Terraform Open (7 × 3) | 21 | |
| Docker Coding | 10 | |
| Kubernetes MCQ (9 × 1) | 9 | |
| Kubernetes Open (2 × 5) | 10 | |
| AWS MCQ (7 × 1) | 7 | |
| **Total** | **58** | |

---

## SRE Lead Answer Pattern (open questions)

For every open question, structure your answer:
1. **What** — define the concept precisely
2. **Why** — why it matters operationally
3. **How** — concrete example (code/YAML/command)
4. **Traps** — what goes wrong, edge cases
