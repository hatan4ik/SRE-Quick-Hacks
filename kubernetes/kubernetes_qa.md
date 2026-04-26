# Kubernetes — Assessment Q&A

---

## MULTIPLE CHOICE (9 questions)

---

### MCQ1. A Pod keeps restarting with `CrashLoopBackOff`. What is the FIRST command to run?

- A) `kubectl get pod <name> -o yaml`
- B) `kubectl logs <name> --previous`
- C) `kubectl describe pod <name>`
- D) `kubectl exec -it <name> -- sh`

**Answer: B**
`--previous` shows logs from the **last crashed container instance** — the only way to see why it died. `describe` shows events (good second step). `exec` won't work if the container keeps crashing.

---

### MCQ2. Which probe, when it fails, stops traffic to a Pod WITHOUT restarting it?

- A) Liveness probe
- B) Startup probe
- C) Readiness probe
- D) Health probe

**Answer: C**
Readiness probe failure → Pod removed from Service Endpoints → no traffic. Pod stays running. Liveness failure → container restart. Startup failure → container restart (used to delay liveness during slow startup).

---

### MCQ3. What does setting `resources.requests` on a container do?

- A) It is the maximum CPU/memory the container is allowed to use
- B) It is used by the scheduler to decide which node to place the Pod on
- C) It triggers an OOMKill if exceeded
- D) It sets the QoS class to Guaranteed

**Answer: B**
`requests` are used for **scheduling decisions**. `limits` are enforced at runtime (OOMKill for memory, throttle for CPU). A Pod is `Guaranteed` only when `requests == limits` for ALL containers.

---

### MCQ4. A Deployment with 3 replicas creates 1 new Pod, waits for it to be Ready, then terminates 1 old Pod. What strategy is this?

- A) `Recreate`
- B) `RollingUpdate` with `maxSurge=1, maxUnavailable=0`
- C) `RollingUpdate` with `maxSurge=0, maxUnavailable=1`
- D) Blue/Green

**Answer: B**
`maxSurge=1` allows 1 extra Pod above desired (creates new first). `maxUnavailable=0` means no old Pod is deleted until the new one is Ready. This is zero-downtime rolling update.

---

### MCQ5. Which object is correct for a stateful app requiring stable network identities and ordered pod startup?

- A) Deployment
- B) DaemonSet
- C) StatefulSet
- D) ReplicaSet

**Answer: C**
StatefulSet gives each Pod a stable hostname (`pod-0`, `pod-1`), stable PVC per pod, and ordered startup/shutdown. Use for databases, Kafka, ZooKeeper. Deployment Pods are interchangeable with random names.

---

### MCQ6. A `ClusterIP` Service exposes a Deployment internally. What do you need to make it accessible from the internet via an AWS ALB?

- A) Change type to `NodePort`
- B) Change type to `LoadBalancer`
- C) Create an Ingress with an IngressClass pointing to the AWS Load Balancer Controller
- D) Change type to `ExternalName`

**Answer: C**
For AWS ALB specifically: deploy the AWS Load Balancer Controller and use an `Ingress` resource with `ingressClassName: alb`. `LoadBalancer` type creates an NLB (or classic ELB) by default, not an ALB.

---

### MCQ7. What is the purpose of a `PodDisruptionBudget` (PDB)?

- A) Limit CPU usage during disruptions
- B) Guarantee a minimum number of Pods remain available during voluntary disruptions (node drain, cluster upgrade)
- C) Prevent Pods from being evicted due to memory pressure
- D) Set the maximum number of Pods in a namespace

**Answer: B**
PDB is a policy that says "at least N Pods of this selector must be running." Node drains and cluster upgrades respect PDBs. It does **NOT** protect against involuntary disruptions (node failure).

---

### MCQ8. You want a container to run on EVERY node, including new nodes added later. Which controller?

- A) Deployment with `replicas: 100`
- B) StatefulSet
- C) DaemonSet
- D) CronJob

**Answer: C**
DaemonSet ensures exactly one Pod per node (matching a node selector if specified). Used for log collectors (Fluentd), monitoring agents (Datadog/Prometheus node-exporter), CNI plugins.

---

### MCQ9. Which RBAC combination grants permissions to a ServiceAccount within a specific namespace only?

- A) `ClusterRole` + `ClusterRoleBinding`
- B) `Role` + `RoleBinding`
- C) `Role` + `ClusterRoleBinding`
- D) `ServiceAccountPolicy`

**Answer: B**
`Role` defines permissions scoped to one namespace. `RoleBinding` attaches it to a subject within that namespace. `ClusterRole` + `ClusterRoleBinding` is cluster-wide. `ClusterRole` + `RoleBinding` is a valid pattern (reuse a ClusterRole but scope the binding to one namespace).

---

## OPEN QUESTIONS (2 questions)

---

### Q10. Explain Kubernetes probes in detail. Configure them for a production web application.

**Answer:**

Three probe types control container health and traffic:

#### 1. Startup Probe
Used when a container takes a long time to initialize. **Disables liveness and readiness** until it succeeds. On failure, container is killed and restarted.

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30   # 30 × 10s = 5 min max startup time
  periodSeconds: 10
```

#### 2. Liveness Probe
Detects if a container is stuck (deadlock, corrupted state). On failure → **container is restarted**.

```yaml
livenessProbe:
  httpGet:
    path: /healthz/live
    port: 8080
  periodSeconds: 20
  failureThreshold: 3
  timeoutSeconds: 5
```

**Warning:** Do NOT use liveness to check external dependencies (DB, cache). If the DB goes down, you don't want all your pods restarting — that makes the outage worse.

#### 3. Readiness Probe
Detects if the container can serve traffic (DB connected, cache warm). On failure → **Pod removed from Service endpoints** (no restart). Critical for rolling deployments — new Pods only receive traffic when Ready.

```yaml
readinessProbe:
  httpGet:
    path: /healthz/ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3
  successThreshold: 1
```

#### Full production Deployment example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: api
          image: myapp/api:1.2.3
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              memory: 512Mi      # no CPU limit — avoids throttling latency-sensitive apps
          startupProbe:
            httpGet:
              path: /healthz
              port: 8080
            failureThreshold: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz/live
              port: 8080
            periodSeconds: 20
            failureThreshold: 3
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /healthz/ready
              port: 8080
            periodSeconds: 10
            failureThreshold: 3
```

#### Probe mechanisms
| Mechanism | Description |
|---|---|
| `httpGet` | HTTP GET — success if 200–399 |
| `tcpSocket` | TCP connection attempt |
| `exec` | Run command inside container — success if exit 0 |
| `grpc` | gRPC health check protocol |

---

### Q11. Explain Kubernetes RBAC. Write manifests to give a ServiceAccount read-only access to Pods in the `default` namespace.

**Answer:**

RBAC controls what actions subjects (Users, Groups, ServiceAccounts) can perform on Kubernetes API resources.

#### Core objects

| Object | Scope | Purpose |
|---|---|---|
| `Role` | Namespace | Defines allowed verbs on resources in one namespace |
| `ClusterRole` | Cluster-wide | Same but across all namespaces or for non-namespaced resources |
| `RoleBinding` | Namespace | Binds a Role or ClusterRole to subjects in one namespace |
| `ClusterRoleBinding` | Cluster-wide | Binds a ClusterRole to subjects cluster-wide |

**Verbs:** `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`, `deletecollection`

#### Full manifest

```yaml
# 1. ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-runner
  namespace: default
---
# 2. Role — read-only pod permissions
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
  - apiGroups: [""]              # "" = core API group (pods, services, configmaps)
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
---
# 3. RoleBinding — bind Role to ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-runner-pod-reader
  namespace: default
subjects:
  - kind: ServiceAccount
    name: ci-runner
    namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

#### Verify

```bash
kubectl auth can-i list pods \
  --namespace default \
  --as system:serviceaccount:default:ci-runner
# yes

kubectl auth can-i delete pods \
  --namespace default \
  --as system:serviceaccount:default:ci-runner
# no
```

#### Reusable pattern — ClusterRole + RoleBinding

Define one `ClusterRole`, bind it per namespace with `RoleBinding` (does NOT grant cluster-wide access):

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-reader
rules:
  - apiGroups: [""]
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-runner-pod-reader
  namespace: production        # scoped to this namespace only
subjects:
  - kind: ServiceAccount
    name: ci-runner
    namespace: production
roleRef:
  kind: ClusterRole            # referencing ClusterRole, not Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

#### Common RBAC mistakes
1. Using `ClusterRoleBinding` when `RoleBinding` is sufficient → accidental cluster-wide access.
2. Forgetting `apiGroups` — Deployments are in `apps`, not `""`. Pods/Services/ConfigMaps are in `""`.
3. Using `*` for verbs or resources in production — violates least privilege.
4. Binding to `system:authenticated` group — grants permissions to ALL authenticated users.

---

## Cheat Sheet

### Requests vs Limits vs QoS

```yaml
resources:
  requests:
    cpu: "250m"      # scheduler uses this to find a node
    memory: "128Mi"  # guaranteed to the container
  limits:
    cpu: "500m"      # throttled if exceeded (NOT killed)
    memory: "256Mi"  # OOMKilled if exceeded
```

| QoS Class | Condition | Eviction priority |
|---|---|---|
| `Guaranteed` | `requests == limits` for ALL containers | Last evicted |
| `Burstable` | At least one container has `requests != limits` | Middle |
| `BestEffort` | No requests or limits set | First evicted |

**Eviction order under memory pressure:** BestEffort → Burstable → Guaranteed

### Probes summary

| Probe | Failure action | Use case |
|---|---|---|
| `startupProbe` | Restart container | Slow-starting apps — disables liveness/readiness during startup |
| `livenessProbe` | Restart container | Detect deadlock/hung process |
| `readinessProbe` | Remove from Service endpoints | App not ready (warming up, DB not connected) |

### Troubleshooting states

| State | First command | Common causes |
|---|---|---|
| `Pending` | `kubectl describe pod` | Insufficient resources, unsatisfied affinity/taint, PVC unbound |
| `CrashLoopBackOff` | `kubectl logs --previous` | App exits, bad CMD, missing env/secret, liveness probe too aggressive |
| `ImagePullBackOff` | `kubectl describe pod` | Wrong image name/tag, missing imagePullSecret, registry down |
| No traffic | `kubectl get endpoints` | Selector mismatch, pods not Ready, wrong targetPort, NetworkPolicy |

### Key kubectl commands

```bash
kubectl get pods -n <ns> -o wide
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --previous          # crashed container logs
kubectl logs <pod> -n <ns> -c <container>      # specific container
kubectl exec -it <pod> -n <ns> -- sh
kubectl top pods -n <ns>                        # requires metrics-server
kubectl get events --sort-by='.lastTimestamp' -n <ns>
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl auth can-i <verb> <resource> --as=system:serviceaccount:<ns>:<sa>
kubectl get endpoints <service> -n <ns>         # debug Service → Pod wiring
```

### Service types

| Type | Accessible from | Use case |
|---|---|---|
| `ClusterIP` | Inside cluster only | Internal microservices |
| `NodePort` | Node IP + port (30000–32767) | Dev/testing |
| `LoadBalancer` | External via cloud LB (NLB on AWS) | Production TCP/UDP |
| `ExternalName` | DNS alias | Point to external service |
| Ingress (ALB) | External HTTP/HTTPS | Production web traffic with path/host routing |

### HPA

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Requires `metrics-server`. CPU utilization is calculated against `requests` — pods without requests cannot be scaled by CPU HPA.

### NetworkPolicy (default: all pods can talk to all pods)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-netpol
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - port: 5432
```
