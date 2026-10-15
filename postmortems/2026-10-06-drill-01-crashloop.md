# Postmortem: DRILL-01 billing-worker crash loop (tenant-a)

**Date:** 2026-10-06 · **Type:** planned drill (lab, not production) · **Severity:** critical alert, no customer impact
**On-call:** Princewill Agbodike

## Summary
A "bad release" of `billing-worker` in tenant-a exited on start because a required environment variable was missing. Kubernetes restarted it repeatedly (Error → CrashLoopBackOff). The new `PodCrashLooping` alert fired about 4 minutes after deploy. Root cause was found from the container logs; the release was removed.

## Timeline (local time)
| Time | Event |
|---|---|
| 19:59 | Bad release applied (`drills/drill-01-crashloop.yaml`) |
| 20:00 | `kubectl get pods -n tenant-a` → `billing-worker 0/1 Error`, 2 restarts in 39 s; `inference-api` 1/1 Running (blast radius: none) |
| 20:01 | `kubectl logs --previous` failed: previous container already removed by containerd |
| 20:02 | `kubectl logs` (current container, already crashed) → `FATAL: missing env DATABASE_URL` |
| 20:02 | `increase(kube_pod_container_status_restarts_total[15m])` = 2.4 (> 2) |
| 20:03:35 | Alert **Pending** (`for: 1m`) |
| 20:03:51 | Alert **Firing** |
| 20:04 | Mitigation: `kubectl delete -f drills/drill-01-crashloop.yaml` |
| 20:04–20:10+ | Alert kept firing after the pod was gone (see lessons) |

## Root cause
Application configuration bug: the release did not provide `DATABASE_URL`, so the process exited with an error on start. Not a platform issue (node, network, memory and image were all fine). Restarts can never fix this class of failure.

## What went well
- The alert fired on its own, ~4 minutes after the bad deploy.
- Triage checked blast radius first, then found the cause from logs in ~3 minutes.

## What didn't
- `logs --previous` was unavailable because exited containers are cleaned up quickly; without central logging (Loki/ELK) the evidence can disappear.
- The alert stayed **Firing after the fix**: `increase(...[15m])` still sees the old restarts in its 15-minute window, so it only clears once the window passes.

## Action items
1. Ship pod logs off-node (Loki) so crash logs survive restarts.
2. Consider a faster-clearing crash-loop rule (e.g. `kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} == 1`) alongside the restart-count rule.
3. Release checklist: validate required env vars / Secrets before deploy.
