#!/usr/bin/env bash

# set -euxo pipefail

# The kind cluster is configured to map NodePort 30080 to the host (see k8s/kind-config.yaml)
# The ingress-nginx controller should use NodePort 30080 for HTTP traffic

# If you need to patch the ingress-nginx controller to use NodePort 30080, run:
# kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p='[{"op": "replace", "path": "/spec/ports/0/nodePort", "value": 30080}]'

#INGRESS_PORT=80
PORT="${INGRESS_PORT:-30080}"
#PORT="${INGRESS_PORT:-$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo 80)}"
# docker ps --filter "name=microsvcs" --format "{{.Names}}: {{.Ports}}"

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