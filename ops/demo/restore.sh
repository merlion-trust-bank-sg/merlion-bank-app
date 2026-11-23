#!/usr/bin/env bash
# Undo ops/demo/trigger-alert.sh: the HPA takes over again from 2 replicas.
set -euo pipefail

CLUSTER="g4-merlion-staging"
CTX="$(kubectl config current-context)"
case "$CTX" in *"$CLUSTER"*) ;; *) echo "Current context is $CTX, not $CLUSTER. Refusing." >&2; exit 1 ;; esac

kubectl -n bank scale deployment/frontend --replicas=2
kubectl -n bank rollout status deployment/frontend --timeout=3m
