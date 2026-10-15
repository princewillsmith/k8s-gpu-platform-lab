#!/usr/bin/env bash
# Simulate an 8x H100 node: advertise nvidia.com/gpu capacity and taint it so only GPU workloads land there.
set -euo pipefail
NODE=gpu-prod-worker2
kubectl taint node "$NODE" nvidia.com/gpu=present:NoSchedule --overwrite
kubectl proxy --port=8001 >/dev/null 2>&1 & PROXY=$!
trap 'kill $PROXY' EXIT
sleep 2
curl -s -o /dev/null -w "capacity patch: HTTP %{http_code}\n" \
  -H "Content-Type: application/json-patch+json" -X PATCH \
  --data '[{"op":"add","path":"/status/capacity/nvidia.com~1gpu","value":"8"}]' \
  "http://127.0.0.1:8001/api/v1/nodes/$NODE/status"
