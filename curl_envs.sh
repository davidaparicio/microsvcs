#!/usr/bin/env bash

set -euxo pipefail

# Development
curl http://red.dev.127.0.0.1.nip.io
curl http://blue.dev.127.0.0.1.nip.io
curl http://green.dev.127.0.0.1.nip.io
curl http://yellow.dev.127.0.0.1.nip.io

# Staging
curl http://red.stg.127.0.0.1.nip.io
curl http://blue.stg.127.0.0.1.nip.io
curl http://green.stg.127.0.0.1.nip.io
curl http://yellow.stg.127.0.0.1.nip.io

# Production
curl http://red.prd.127.0.0.1.nip.io
curl http://blue.prd.127.0.0.1.nip.io
curl http://green.prd.127.0.0.1.nip.io
curl http://yellow.prd.127.0.0.1.nip.io