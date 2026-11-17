#!/usr/bin/env bash
# Send customer-like traffic through the ALB, so the SLI panels have data. The staging loadgenerator
# calls the frontend inside the cluster and never reaches the ALB.
# Status codes only: nothing from the responses is printed (CI-log and demo hygiene).
#
#   ops/demo/traffic.sh                                   staging, 2 requests a second
#   ops/demo/traffic.sh https://merlion.sctp-sandbox.com  prod
set -euo pipefail

URL="${1:-https://merlion-staging.sctp-sandbox.com}"
echo "GET $URL/login twice a second. Ctrl-C to stop."
while true; do
  printf '%s %s\n' "$(date +%H:%M:%S)" "$(curl -s -o /dev/null -m 5 -w '%{http_code}' "$URL/login" || true)"
  sleep 0.5
done
