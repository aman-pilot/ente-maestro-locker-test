#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-locker-seeded-flow.sh"
readonly runner="${LOCKER_SEEDED_RUNNER:-$workspace_root/scripts/run-locker-seeded-suite.sh}"
selected_flow="$($selector "${LOCKER_SELECTED_FLOW:-all}")"
readonly selected_flow

if [[ "$selected_flow" == all ]]; then
    exec "$runner" "$@"
fi

exec "$runner" --only-flow "$selected_flow" "$@"
