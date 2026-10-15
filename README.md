# Kubernetes GPU Platform Lab

A production-style, multi-tenant Kubernetes platform I built on my laptop with [kind](https://kind.sigs.k8s.io/). It has a tainted GPU node pool, tenant quotas and RBAC, zero-trust networking, Prometheus and Grafana monitoring, and incident drills written up as postmortems.

> This is a lab, not production. The GPUs are simulated: the GPU node advertises 8 `nvidia.com/gpu` through a status patch, so the scheduler, quotas and alerts behave as they would on a real GPU cluster.

## What's in it

| Area | What I built | Files |
|---|---|---|
| Cluster | 3-node kind cluster: control plane, CPU worker, GPU worker (tainted, labelled H100, 8 simulated GPUs) | `cluster/` |
| Tenancy | Two customer namespaces with ResourceQuota (CPU, memory, 4 GPUs, pods), LimitRange defaults and read-only RoleBindings | `tenants/` |
| Workloads | Inference API with 2 replicas, zero-downtime rolling updates, probes, PodDisruptionBudget and HPA; a GPU training Job that asks for 2 GPUs and tolerates the taint | `workloads/` |
| Networking | Default-deny ingress per tenant, with only ingress-nginx allowed to reach the API | `workloads/network-policy.yaml` |
| Monitoring | kube-prometheus-stack trimmed to fit an 8 GB laptop, plus my own alert rules for memory pressure, crash loops and GPU nodes going NotReady | `platform/` |
| Incidents | Planned failure drills, triaged with kubectl and Prometheus, then written up as blameless postmortems | `drills/`, `postmortems/` |

## Incidents I worked through

- **Grafana restart loop.** The default liveness probe killed Grafana before it finished starting. I fixed it with a longer `initialDelaySeconds`. Then the pod hit `OOMKilled` (exit 137) at a 256Mi limit, and I raised the limit to 512Mi based on measured peak usage.
- **Bad image rollout.** I shipped a broken image tag on purpose. The rollout stalled in `ImagePullBackOff`, but the old pods kept serving because `maxUnavailable` was 0. I found the `NotFound` error in Events and rolled back with `kubectl rollout undo`.
- **Node drain blocked.** Draining the CPU worker evicted one API pod, then the PodDisruptionBudget refused the second eviction. The replacement pod stayed Pending (`FailedScheduling`) because the only other workers were the cordoned node and the tainted GPU node. Uncordoning brought it back to 2/2. Lesson: a PDB only keeps maintenance safe if the pool has spare capacity.
- **Bad release crash loop (DRILL-01).** A release with a missing env var crash-looped. My `PodCrashLooping` alert fired about 4 minutes after the deploy, and I found the root cause in the logs within about 3 minutes. Postmortem in `postmortems/`.

## Run it

Needs Docker, kind, kubectl and helm.

```bash
kind create cluster --config cluster/kind-prod.yaml
./cluster/gpu-node.sh                       # taint the GPU worker and advertise 8 GPUs

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace -f platform/ingress-values.yaml
helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system -f platform/metrics-server-values.yaml
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace \
  -f platform/monitoring-values.yaml --wait --timeout 10m

kubectl apply -f tenants/
kubectl apply -f workloads/
kubectl apply -f platform/alert-rules.yaml
```

Set your own Grafana password in `platform/monitoring-values.yaml` before you install.

## Rules I followed

- Every change goes through git and manifests. No `kubectl edit` on live objects.
- Every incident gets a severity, a timeline, a customer update and a postmortem.
