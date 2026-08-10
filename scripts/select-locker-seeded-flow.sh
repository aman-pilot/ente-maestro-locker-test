#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly registry="$workspace_root/locker/product-flows.v1.json"

if [[ $# -gt 1 ]]; then
    echo "Usage: scripts/select-locker-seeded-flow.sh [all|flow-name]" >&2
    exit 2
fi

requested_flow=${1:-all}
if [[ "$requested_flow" == all ]]; then
    echo all
    exit 0
fi

if ! jq --exit-status --arg flow "$requested_flow" '
    [
      .classifications.hostedCandidate[],
      (.classifications.hostedUnresolved | keys[])
    ]
    | index($flow) != null
  ' "$registry" > /dev/null; then
    printf 'Unknown targeted Locker flow: %s\n' "$requested_flow" >&2
    exit 2
fi

echo "$requested_flow"
