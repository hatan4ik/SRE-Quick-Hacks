# Drill Plan

## Day-Before Review

Spend 2 hours maximum. Do not try to learn every edge case.

1. Terraform state/backends/import/modules: 30 minutes.
2. Dockerfile writing from memory: 20 minutes.
3. Kubernetes troubleshooting scenarios: 45 minutes.
4. AWS networking/IAM/high availability: 25 minutes.

## Fast Recall Prompts

Answer these out loud without notes.

1. Terraform plan shows destroy/create after a rename. What do you do?
2. Terraform state contains secrets. How do you reduce risk?
3. Docker container cannot reach `localhost:5432`. Why?
4. Docker image is huge. What changes reduce it?
5. Pod is Pending. What are five causes?
6. Pod is CrashLoopBackOff. What commands do you run?
7. Service has no endpoints. What do you check?
8. Readiness vs liveness?
9. Security group vs NACL?
10. Public vs private subnet?
11. ALB target unhealthy. What do you check?
12. EC2 app needs S3 access. What is the secure pattern?

## SRE Lead Answer Pattern

For open questions, answer in this order:

1. State the likely failure mode.
2. Name the first commands/signals you would inspect.
3. Explain immediate mitigation or rollback.
4. Explain permanent fix.
5. Mention safety: blast radius, observability, ownership, and review.

Example:

Question: A rollout caused 5xx errors. What do you do?

Answer shape:

- Confirm impact with ALB/app metrics and logs.
- Compare error spike to deployment timeline.
- Stop rollout or roll back if impact is active.
- Inspect health checks, target group, app logs, dependency latency, resource saturation.
- Fix root cause, add regression coverage/alerting, and document incident timeline.

## Things Not To Do In The Real Assessment

- Do not use AI tools if prohibited.
- Do not search for exact answers if prohibited.
- Do not paste memorized answers that do not address the exact question.
- Do not overcomplicate: clear first principles score better than vague buzzwords.
