# Mock 90-Minute SRE/DevOps Assessment

Use this before the real assessment. Set a 90-minute timer. Do not look at the answer key until finished.

This is original practice material, not actual assessment content.

## Section 1: Terraform

Suggested time: 25 minutes.

### Terraform MCQ 1

You manage a list of IAM users with `count`. A new user is inserted at the beginning of the list. What is the main risk?

A. Terraform will ignore all users  
B. Terraform may propose replacing or renaming resources because indexes changed  
C. Terraform will automatically switch to `for_each`  
D. Terraform will disable state locking

### Terraform Open 1

Your team uses local Terraform state and two engineers accidentally apply changes at the same time. Explain the failure mode and propose a better production setup.

### Terraform Open 2

An S3 bucket exists in AWS but is not managed by Terraform. You need Terraform to manage it without recreating it. What steps do you take?

### Terraform Open 3

You changed the name of a Terraform resource block and now the plan shows destroy/create. How do you preserve the existing resource?

### Terraform Open 4

How would you design Terraform code for dev, staging, and production while minimizing copy/paste?

### Terraform Open 5

What are the risks of using `ignore_changes` broadly?

### Terraform Open 6

Explain provider version pinning and why `.terraform.lock.hcl` should usually be committed.

### Terraform Open 7

What does a good Terraform CI/CD workflow look like for production?

## Section 2: Docker Coding

Suggested time: 15 minutes.

You are given a Python API with:

- `requirements.txt`
- `app/main.py`
- It listens on port `8080`
- Start command: `python -m app.main`
- Health endpoint: `/healthz`

Write a Dockerfile that:

- Uses a slim Python base image
- Installs dependencies efficiently
- Runs as a non-root user
- Exposes port 8080
- Uses an exec-form command
- Avoids pip cache

Bonus: include a healthcheck.

## Section 3: Kubernetes

Suggested time: 30 minutes.

### Kubernetes MCQ 1

A Pod is `Pending`. Which command is most useful first?

A. `kubectl logs pod`  
B. `kubectl describe pod`  
C. `kubectl delete namespace`  
D. `kubectl rollout undo`

### Kubernetes MCQ 2

What does a readiness probe control?

A. Whether the container should be restarted  
B. Whether the Pod receives Service traffic  
C. Whether an image can be pulled  
D. Whether the node joins the cluster

### Kubernetes MCQ 3

Your Service has no endpoints. What is a likely cause?

A. Service selector does not match Pod labels  
B. Too many ConfigMaps  
C. CPU limit is too low  
D. `kubectl` is outdated

### Kubernetes MCQ 4

What does `kubectl logs --previous` help debug?

A. Previous kubeconfig context  
B. Previous crashed container instance  
C. Previous Helm chart version only  
D. Previous Service selector

### Kubernetes MCQ 5

What happens when a container exceeds its memory limit?

A. It can be OOMKilled  
B. It is only throttled  
C. It is automatically moved live to another node  
D. The namespace is deleted

### Kubernetes MCQ 6

Which object is best for one Pod per node?

A. Deployment  
B. DaemonSet  
C. Job  
D. Ingress

### Kubernetes MCQ 7

What is a PDB used for?

A. Prevent all application crashes  
B. Limit voluntary disruptions below availability requirements  
C. Store passwords  
D. Route HTTP paths

### Kubernetes MCQ 8

Which object is commonly used for HTTP path routing into Services?

A. ConfigMap  
B. Ingress  
C. PVC  
D. Secret

### Kubernetes MCQ 9

What do CPU requests affect directly?

A. Scheduling and HPA CPU utilization baseline  
B. Docker image size  
C. DNS record TTL  
D. Secret encryption

### Kubernetes Open 1

A new Deployment rollout is stuck. Pods exist but are not Ready. Walk through your debugging process.

### Kubernetes Open 2

Explain a safe production rollout strategy for a stateless service.

## Section 4: AWS

Suggested time: 15 minutes.

### AWS MCQ 1

What is the difference between a security group and a NACL?

A. Security groups are stateless; NACLs are stateful  
B. Security groups are stateful and ENI-level; NACLs are stateless and subnet-level  
C. Both are only IAM features  
D. NACLs replace route tables

### AWS MCQ 2

What allows private subnet instances to initiate outbound internet access?

A. Internet Gateway directly attached to instance  
B. NAT Gateway with route table entry  
C. S3 bucket policy  
D. Route 53 private hosted zone only

### AWS MCQ 3

What is the safest way for an EC2 instance to access S3?

A. Hardcoded access keys  
B. IAM role through instance profile  
C. Root account access key  
D. Public bucket policy

### AWS MCQ 4

What does RDS Multi-AZ mainly provide?

A. High availability/failover  
B. Unlimited read scaling  
C. Object storage  
D. DNS hosting

### AWS MCQ 5

Which S3 setting helps recover from accidental overwrite?

A. Versioning  
B. Public ACL  
C. Website hosting  
D. Transfer acceleration only

### AWS MCQ 6

An ALB target is unhealthy. What should you check?

A. Health check path/port, app listening, security groups, target logs  
B. Only IAM password policy  
C. Only S3 lifecycle policy  
D. Only Route 53 TTL

### AWS MCQ 7

Which IAM statement overrides an allow?

A. Explicit deny  
B. Tag value  
C. Oldest policy  
D. Region setting

## Answer Key

## Terraform Answers

### Terraform MCQ 1

Answer: B.

`count` indexes are positional. Inserting an element at the beginning can shift indexes and make Terraform think existing resources changed identity. For named resources, prefer `for_each` with stable keys.

### Terraform Open 1

Good answer:

Local state has no shared locking or authoritative team state. Concurrent applies can race, overwrite state, or produce infrastructure/state mismatch. Use a remote backend such as S3 with locking, restricted access, versioning, encryption, CI-generated plans, peer review, and controlled applies.

### Terraform Open 2

Good answer:

Write a matching `resource` block, import the bucket into that resource address, run plan, reconcile config with real settings, and apply only after the plan shows no unexpected destructive changes. Use either `terraform import` or an `import` block.

### Terraform Open 3

Good answer:

Use a `moved` block or `terraform state mv` to preserve state mapping from old address to new address, then run plan to confirm no replacement.

### Terraform Open 4

Good answer:

Use reusable modules and separate root modules or state per environment. Keep environment-specific values in tfvars or config files, avoid shared production/non-production state, use CI gates, and keep module interfaces stable.

### Terraform Open 5

Good answer:

Broad `ignore_changes` can hide real drift, security changes, manual edits, and configuration mistakes. Use only for fields intentionally owned by another system or provider-computed metadata.

### Terraform Open 6

Good answer:

Provider constraints define acceptable versions. `.terraform.lock.hcl` records selected provider versions/checksums for reproducible installs. Commit it so CI and teammates use the same provider selections unless intentionally upgraded.

### Terraform Open 7

Good answer:

Format/validate/static scan, plan in CI, publish plan artifact, require review/approval, apply from controlled pipeline using remote locked state and scoped credentials, log changes, separate environments, and support rollback/import/state operations with care.

## Docker Answer

One good answer:

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

Key points: dependency layer is cached, final process is non-root, command uses exec form, port is documented, pip cache is disabled, and healthcheck is optional.

## Kubernetes Answers

1. B. `kubectl describe pod` shows scheduling/probe/events details.
2. B. Readiness controls whether traffic is sent to the Pod.
3. A. Services select endpoints by matching Pod labels.
4. B. Shows logs from previous terminated container instance.
5. A. Memory limit breach can cause OOMKill.
6. B. DaemonSet.
7. B. PDB limits voluntary disruption.
8. B. Ingress.
9. A. Requests affect scheduling and CPU utilization calculation for HPA.

### Kubernetes Open 1

Good answer:

Check rollout status, describe Deployment/ReplicaSet/Pod, inspect events, check readiness probe failures, logs, config/secret mounts, image version, app port binding, resource pressure, Service dependencies, and recent changes. If production impact exists, roll back while continuing root-cause analysis.

### Kubernetes Open 2

Good answer:

Use Deployment rolling updates with readiness probes, `maxUnavailable: 0` or conservative setting, `maxSurge`, monitoring, logs, alerts, PDB, HPA capacity, canary/progressive rollout where possible, and a fast rollback path.

## AWS Answers

1. B. Security groups are stateful ENI-level; NACLs are stateless subnet-level.
2. B. NAT Gateway plus route table entry.
3. B. IAM role through instance profile.
4. A. RDS Multi-AZ improves failover availability.
5. A. S3 versioning.
6. A. Check health check path/port, app, SGs, and logs.
7. A. Explicit deny.
