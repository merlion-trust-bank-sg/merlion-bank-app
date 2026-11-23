#!/usr/bin/env bash
# Live alert demo, STAGING ONLY: take the frontend away and watch the alerts arrive in Telegram.
#
#   1. Terminal A: ops/demo/traffic.sh          (200s, then 503s after the trigger)
#   2. Terminal B: ops/demo/trigger-alert.sh
#   3. About 4 min: BankServiceDown (frontend); about 2 min after that (~6 min from the trigger): BankAvailabilityFastBurn.
#   4. ops/demo/restore.sh, then RESOLVED messages within about 15 min (measured 13 min on 23 Nov).
#
# Why kubectl and not a PR: this is a failure we inject, not a change we keep, and staging is the
# environment for that. Prod is never changed by hand (HC-2). The Deployment's replica count is owned
# by the HPA, not by Git, so Argo CD doesn't undo the scale-down.
set -euo pipefail

CLUSTER="g4-merlion-staging"
CTX="$(kubectl config current-context)"
case "$CTX" in *"$CLUSTER"*) ;; *) echo "Current context is $CTX, not $CLUSTER. Refusing." >&2; exit 1 ;; esac

kubectl -n bank scale deployment/frontend --replicas=0
echo "frontend scaled to 0 at $(date +%H:%M:%S). Run ops/demo/restore.sh to bring it back."
