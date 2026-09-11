#!/bin/bash
# Pre-Helmsman cleanup for MOSIP DSF
# This script MUST be run BEFORE helmsman --apply when Job images change.
#
# Why: Kubernetes Jobs cannot update spec.template (immutable). Helmsman
# uses kubectl diff when helm-diff is missing; the API then rejects the
# plan with: Job "kernel-keygen" is invalid: spec.template: field is immutable.
# Deleting the Job lets Helm recreate it with the new image.
#
# Usage: ./pre-helmsman-mosip-cleanup.sh [kubeconfig]

set -euo pipefail

if [ $# -ge 1 ]; then
  export KUBECONFIG=$1
fi

delete_job() {
  local ns=$1
  local name=$2
  echo "Deleting job ${name} in namespace ${ns}..."
  kubectl -n "$ns" delete job "$name" --ignore-not-found=true
  kubectl -n "$ns" delete job -l "app.kubernetes.io/instance=${name}" --ignore-not-found=true
}

echo "=============================================="
echo "Pre-Helmsman cleanup: deleting immutable Jobs"
echo "=============================================="

delete_job keymanager kernel-keygen
delete_job ida ida-keygen
delete_job idrepo idrepo-saltgen
delete_job regproc regproc-salt
delete_job masterdata-loader masterdata-loader

echo "Waiting for job pods to terminate..."
sleep 5

echo "Pre-Helmsman MOSIP cleanup complete"
