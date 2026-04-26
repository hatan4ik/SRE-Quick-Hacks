# Kubernetes — FAANG SRE Lead Level

These questions probe production war experience, security depth, and architectural judgment — not textbook knowledge.

---

## Q1. Walk me through debugging a latency spike with no obvious cause. The service looks healthy — pods are running, probes pass, CPU is low.

**Answer — systematic observability approach, not random guessing.**

**Immediately establish: is this latency increase real and where in the stack?**
```bash
# 1. Check if it's at the load balancer (before hitting pods)
#    AWS ALB metrics: TargetResponseTime vs RequestCount
#    If ALB TargetResponseTime is spiking → it's definitely the app or a downstream

# 2. Check which pods are slow (not all pods may be affected)
kubectl top pods -n <ns> --sort-by=cpu
kubectl top pods -n <ns> --sort-by=memory
```

**Check for GC / memory pressure:**
```bash
# Is memory near limit? GC pauses cause latency spikes
kubectl describe pod <pod> -n <ns> | grep -A5 "Limits\|Requests"
# Look for OOMKilled in recent events — signals the pod was at the edge
kubectl get events -n <ns> --sort-by='.lastTimestamp' | grep OOM
```

**Check for throttling — CPU throttling causes latency but doesn't show as high CPU:**
```bash
# Prometheus query (if available)
rate(container_cpu_cfs_throttled_periods_total[5m]) /
rate(container_cpu_cfs_periods_total[5m])
# If > 0.25 (25%), you're CPU throttled — raise limits or optimize
```

**Check downstream dependencies:**
```bash
# Is the database slow?
kubectl exec -it <pod> -- curl -s http://localhost:8080/metrics | grep db_query_duration
# Or check RDS CloudWatch: ReadLatency, DatabaseConnections at the time of the spike
```

**Check for noisy neighbors:**
```bash
# Another pod on the same node consuming resources
kubectl get pods -o wide -A | grep <node-name>
kubectl describe node <node-name> | grep -A20 "Allocated resources"
```

**Check network:**
```bash
# DNS resolution slowness is a common hidden cause
kubectl exec -it <pod> -- time nslookup downstream-service.namespace.svc.cluster.local
# If DNS is slow: CoreDNS may be overwhelmed — check CoreDNS pod CPU/memory
kubectl top pods -n kube-system -l k8s-app=kube-dns
```

**Check if it's a specific pod (bad JVM heap, leaked connection pool):**
```bash
# Compare response times across replicas using kubectl port-forward
kubectl port-forward pod/<pod-0> 8080:8080 &
time curl localhost:8080/api/health
```

**Resolution path (by cause):**
| Root cause | Fix |
|------------|-----|
| CPU throttling | Raise CPU limit, or set no limit with request-only (careful) |
| GC pressure | Increase memory limit, tune GC flags |
| DB connection exhaustion | Add RDS Proxy, tune pool size |
| Noisy neighbor | PodAntiAffinity, dedicated node group |
| DNS slow | ndots:5 optimization, NodeLocal DNSCache |
| Long GC pauses | Startup probe instead of liveness to avoid restart loops |

---

## Q2. Explain Pod Security. What does `securityContext` do and what are the most important fields for a production workload?

**Answer:**

Security context controls the security settings of a container/pod at runtime. It is the primary container hardening mechanism in Kubernetes.

**Pod-level `securityContext`** (applies to all containers):
```yaml
spec:
  securityContext:
    runAsNonRoot: true          # reject if container would run as UID 0
    runAsUser: 1000             # UID to run as
    runAsGroup: 1000            # GID
    fsGroup: 1000               # GID for mounted volumes (files owned by this GID)
    seccompProfile:
      type: RuntimeDefault      # apply default seccomp syscall filter
```

**Container-level `securityContext`** (overrides pod-level):
```yaml
containers:
  - name: api
    securityContext:
      allowPrivilegeEscalation: false   # cannot gain more privs than parent (SUID/sudo)
      readOnlyRootFilesystem: true       # filesystem is read-only (force writes to volumes)
      capabilities:
        drop: ["ALL"]                    # drop ALL Linux capabilities
        add: ["NET_BIND_SERVICE"]        # add back only what's needed (e.g. bind <1024)
```

**Most impactful fields ranked by blast-radius reduction:**

| Field | What it prevents |
|-------|-----------------|
| `allowPrivilegeEscalation: false` | Container cannot escalate to root via SUID binary |
| `runAsNonRoot: true` | Catches Dockerfiles that forgot `USER` instruction |
| `readOnlyRootFilesystem: true` | Attacker cannot write malware to disk; catches misconfig |
| `capabilities: drop: [ALL]` | Removes raw socket, kernel module loading, etc. |
| `seccompProfile: RuntimeDefault` | Blocks ~300 obscure syscalls attackers exploit |

**Pod Security Admission (PSA) — cluster-level enforcement:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted    # blocks non-compliant pods
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

**Three PSA levels:**
- `privileged` — no restrictions (system namespaces only)
- `baseline` — prevents known privilege escalations
- `restricted` — requires non-root, no privilege escalation, seccomp, dropped capabilities

---

## Q3. How do you do a zero-downtime upgrade of a stateful service (e.g. PostgreSQL) running in Kubernetes?

**Answer — this tests whether you understand the difference between stateless and stateful rollouts.**

**Short answer: you don't use a rolling update for in-place PostgreSQL upgrades.** A StatefulSet rolling update with a primary/replica setup has correctness risks. The safe approach depends on the scenario.

**Scenario A: Minor version upgrade (12.x → 12.y) with replicas**
```bash
# 1. Upgrade replicas first (they can be safely replaced)
kubectl patch statefulset postgres-ha \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":1}}}}'
# partition=1 means only pod[0] is excluded → upgrade replica pods first

# 2. Verify replica is healthy and caught up
kubectl exec postgres-ha-1 -- psql -c "SELECT pg_last_wal_receive_lsn();"

# 3. Trigger failover BEFORE touching primary
kubectl exec postgres-ha-0 -- pg_ctl promote  # or use Patroni: patronictl failover

# 4. Old primary is now replica → upgrade it
kubectl patch statefulset postgres-ha \
  -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
```

**Scenario B: Major version upgrade (13 → 14) — requires `pg_upgrade`**
- Never do this in-place in Kubernetes. Use blue/green:
1. Provision new StatefulSet with Postgres 14
2. Stop writes to old cluster (read-only mode or connection block)
3. Run `pg_upgrade --link` or logical replication to sync data
4. Update application's `DATABASE_URL` secret to point to new cluster
5. Verify and test, then decommission old StatefulSet

**Using Operators (recommended for production):**
Tools like Zalando Postgres Operator, CloudNativePG, or Patroni automate this:
```yaml
apiVersion: "acid.zalan.do/v1"
kind: postgresql
metadata:
  name: prod-postgres
spec:
  teamId: "team-a"
  volume:
    size: 100Gi
  numberOfInstances: 3
  postgresql:
    version: "15"   # operator handles primary election + failover
```

**Key principle:** Stateful upgrades require explicit ordering + verification at each step. Never rely on Kubernetes automated rollout for primary database upgrades.

---

## Q4. Explain Cluster Autoscaler vs Karpenter. When would you choose one over the other?

**Answer:**

**Cluster Autoscaler (CA)**
- The original Kubernetes autoscaler, works with any cloud
- Polls every 10s for unschedulable pods, calculates which node group to scale up
- Scale-down: removes nodes that have been underutilized for >10 min and whose pods can fit elsewhere
- Tied to **pre-defined node groups** (ASGs in AWS) — you define the machine types in advance

```yaml
# cluster-autoscaler deployment config
--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/<cluster>
--balance-similar-node-groups=true
--skip-nodes-with-system-pods=false
```

**Karpenter** (AWS-native, open source)
- Provisions EC2 instances directly (bypasses ASGs) — much faster provisioning (seconds vs minutes)
- Instance type selection is demand-driven: picks the cheapest instance that fits pending pods
- Consolidation: proactively repacks pods onto fewer nodes and terminates excess
- Native Spot interruption handling

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.large", "m5.xlarge", "m4.large", "m4.xlarge"]
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
```

**Decision matrix:**
| Criterion | Cluster Autoscaler | Karpenter |
|-----------|-------------------|-----------|
| Cloud support | Any | AWS (Azure beta) |
| Provisioning speed | 3-5 min | 45-90 sec |
| Instance flexibility | Pre-defined ASG | Any instance family |
| Spot handling | Via Spot ASG | Native, interruption-aware |
| Cost optimization | Manual tuning | Automatic consolidation |
| EKS managed node groups | ✅ | Requires self-managed |
| Operational complexity | Lower | Higher (new CRDs, IAM) |

**Choose CA when:** multi-cloud, using managed node groups, team is new to EKS.
**Choose Karpenter when:** AWS-only, cost optimization is critical, need fast scale-out (e.g. ML training jobs), using Spot extensively.

---

## Q5. What is IRSA and how does it work under the hood? How is it different from a node-level IAM role?

**Answer:**

**Node IAM role (the old/insecure way):**
- EC2 worker node has an IAM role with permissions attached
- ANY pod on that node can call `169.254.169.254` IMDS and get those credentials
- One malicious/compromised pod gets access to all permissions on the node
- Violates least privilege — you can't give pod-A S3 access without giving pod-B the same

**IRSA (IAM Roles for Service Accounts):**
Kubernetes ServiceAccount tokens → OIDC federation → short-lived AWS credentials scoped to a specific IAM role.

**How it works step by step:**
```
1. EKS cluster exposes an OIDC provider endpoint
   e.g. oidc.eks.us-east-1.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE

2. IAM role has a trust policy that allows the OIDC provider to assume it:
{
  "Principal": {
    "Federated": "arn:aws:iam::123:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/..."
  },
  "Condition": {
    "StringEquals": {
      "oidc.eks....:sub": "system:serviceaccount:mynamespace:myserviceaccount"
    }
  }
}

3. Pod's ServiceAccount is annotated with the role ARN:
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myserviceaccount
  namespace: mynamespace
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123:role/my-pod-role

4. EKS mutating webhook injects two things into the pod:
   - AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
   - AWS_ROLE_ARN=arn:aws:iam::123:role/my-pod-role

5. AWS SDK reads these env vars, calls STS AssumeRoleWithWebIdentity,
   returns temporary credentials scoped ONLY to this IAM role.
   Token has a 24h expiry, auto-rotated by the kubelet.
```

**Result:** Each pod gets its own minimal IAM role. Compromise of pod-A does not give access to pod-B's AWS resources.

**Equivalent mechanism in other clouds:**
- GKE: Workload Identity
- AKS: Azure AD Workload Identity
- ECS: Task Role (simpler, no OIDC needed)

---

## Q6. You need to upgrade your EKS cluster from 1.27 to 1.29. Describe your approach.

**Answer — lead-level: this is a process question, not a `eksctl upgrade` question.**

**Constraint: EKS only supports N-1 upgrades. 1.27 → 1.28 → 1.29 requires two upgrade cycles.**

**Pre-upgrade (weeks before):**
```bash
# 1. Check deprecated APIs — breaking change risk
kubectl api-resources
# Use Pluto to scan all manifests for deprecated API versions
pluto detect-helm -owide
pluto detect-files -d ./k8s-manifests

# 2. Review release notes for both versions
# Focus on: removed APIs, scheduler changes, feature gate changes

# 3. Check add-on compatibility
# CoreDNS, kube-proxy, VPC CNI, EBS CSI driver have their own version matrices
# https://docs.aws.amazon.com/eks/latest/userguide/managing-add-ons.html

# 4. Run upgrade in dev/staging first — always
eksctl upgrade cluster --name dev-cluster --version 1.28 --approve
```

**Upgrade sequence:**
```
1. Upgrade Control Plane (AWS manages this)
   eksctl upgrade cluster --name prod --version 1.28

2. Upgrade core add-ons (BEFORE worker nodes)
   eksctl utils update-coredns --cluster prod --version v1.10.1
   eksctl utils update-kube-proxy --cluster prod --version v1.28.x
   eksctl utils update-aws-node --cluster prod --version v1.18.x

3. Upgrade worker nodes (rolling, one node group at a time)
   eksctl upgrade nodegroup --cluster prod --name workers --kubernetes-version 1.28
   # eksctl drain → terminates pods with PDB respect → replaces node → uncordons
```

**During upgrade:**
```bash
# Watch node status
watch kubectl get nodes

# Monitor pods for disruption
kubectl get pods -A --watch | grep -v Running
```

**Rollback plan:**
- AWS does not support downgrading control plane
- Keep old node group running in parallel; re-route traffic if new nodes are broken
- Test with canary traffic on new nodes before draining old group

**Post-upgrade:**
```bash
# Verify all nodes on new version
kubectl get nodes --sort-by='.status.nodeInfo.kubeletVersion'

# Validate no deprecated APIs in use
kubectl get events -A | grep "not served"

# Run smoke test suite
```

---

## Q7. How do you design multi-tenancy in a Kubernetes cluster? What are the isolation mechanisms?

**Answer:**

**Soft multi-tenancy** (same cluster, different teams, trust assumed):
- Namespace-per-team boundary
- RBAC: each team's ServiceAccount can only access their namespace
- ResourceQuota + LimitRange: prevent one team from consuming all cluster resources
- NetworkPolicy: restrict cross-namespace communication
- Pod Security Admission: enforce `restricted` profile per namespace

**ResourceQuota per team:**
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    count/pods: "50"
    count/services: "10"
    persistentvolumeclaims: "5"
```

**LimitRange** (default limits for pods that don't specify):
```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-alpha
spec:
  limits:
    - type: Container
      default:
        cpu: 500m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      max:
        cpu: "4"
        memory: 4Gi
```

**Hard multi-tenancy** (untrusted tenants, e.g. SaaS customers): Kubernetes is NOT designed for this. Use:
- Separate clusters per tenant (expensive but true isolation)
- vcluster (virtual cluster — Kubernetes control plane inside a namespace)
- Capsule or HNC (hierarchical namespaces) for namespace grouping

**Decision framework:**
| Isolation level | Mechanism | Use case |
|-----------------|-----------|----------|
| Namespace + RBAC | Soft | Internal teams, same company |
| + NetworkPolicy | Soft | Teams with different data sensitivity |
| + OPA/Kyverno | Soft+ | Compliance requirements |
| Separate node pools | Medium | Dev vs prod workloads on same cluster |
| vcluster | Strong | SaaS, team wants `kubectl` but no blast radius |
| Separate clusters | Hard | Different security domains, customers |
