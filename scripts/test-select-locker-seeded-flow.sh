#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-locker-seeded-flow.sh"

[[ "$($selector)" == all ]]
[[ "$($selector all)" == all ]]
[[ "$($selector view-collection-and-item-action-menus)" == view-collection-and-item-action-menus ]]
[[ "$($selector rename-and-delete-collections)" == rename-and-delete-collections ]]

if "$selector" logout-extra > /dev/null 2>&1; then
    echo "Unknown flows must not reach the hosted seeded runner" >&2
    exit 1
fi
if "$selector" manage-collection-public-link > /dev/null 2>&1; then
    echo "Deferred paid flows must not reach the hosted seeded runner" >&2
    exit 1
fi
if "$selector" all another-flow > /dev/null 2>&1; then
    echo "The seeded selector must reject multiple scopes" >&2
    exit 1
fi

echo "Locker seeded flow selection tests passed"
