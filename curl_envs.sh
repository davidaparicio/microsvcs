#!/usr/bin/env bash

# set -euxo pipefail

# 1. Patched the ingress-nginx service to use NodePort 30080 (which your kind cluster maps to the host)
# 2. Updated curl_envs.sh to use port 30080 by default (configurable via INGRESS_PORT env var)

# If you need to change the NodePort for ingress-nginx controller, uncomment and modify the line below
# kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}]'

PORT="${INGRESS_PORT:-30080}"

# Development
curl "http://red.dev.127.0.0.1.nip.io:${PORT}/version"
curl "http://blue.dev.127.0.0.1.nip.io:${PORT}/version"
curl "http://green.dev.127.0.0.1.nip.io:${PORT}/version"
curl "http://yellow.dev.127.0.0.1.nip.io:${PORT}/version"

# Staging
curl "http://red.stg.127.0.0.1.nip.io:${PORT}/version"
curl "http://blue.stg.127.0.0.1.nip.io:${PORT}/version"
curl "http://green.stg.127.0.0.1.nip.io:${PORT}/version"
curl "http://yellow.stg.127.0.0.1.nip.io:${PORT}/version"

# Production
curl "http://red.prd.127.0.0.1.nip.io:${PORT}/version"
curl "http://blue.prd.127.0.0.1.nip.io:${PORT}/version"
curl "http://green.prd.127.0.0.1.nip.io:${PORT}/version"
curl "http://yellow.prd.127.0.0.1.nip.io:${PORT}/version"