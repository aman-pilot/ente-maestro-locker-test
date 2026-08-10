#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly hosted_runner="$workspace_root/scripts/run-locker-seeded-hosted.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$@" > "$LOCKER_HOSTED_TEST_LOG"' \
    > "$temp_dir/runner"
chmod +x "$temp_dir/runner"

LOCKER_HOSTED_TEST_LOG="$temp_dir/all.log" \
LOCKER_SEEDED_RUNNER="$temp_dir/runner" \
LOCKER_SELECTED_FLOW=all \
    "$hosted_runner" --apk /tmp/locker.apk
printf '%s\n' --apk /tmp/locker.apk > "$temp_dir/expected-all.log"
diff -u "$temp_dir/expected-all.log" "$temp_dir/all.log"

LOCKER_HOSTED_TEST_LOG="$temp_dir/target.log" \
LOCKER_SEEDED_RUNNER="$temp_dir/runner" \
LOCKER_SELECTED_FLOW=view-collection-and-item-action-menus \
    "$hosted_runner" --apk /tmp/locker.apk
printf '%s\n' \
    --only-flow view-collection-and-item-action-menus \
    --apk /tmp/locker.apk \
    > "$temp_dir/expected-target.log"
diff -u "$temp_dir/expected-target.log" "$temp_dir/target.log"

if LOCKER_HOSTED_TEST_LOG="$temp_dir/invalid.log" \
    LOCKER_SEEDED_RUNNER="$temp_dir/runner" \
    LOCKER_SELECTED_FLOW=unknown-flow \
        "$hosted_runner" --apk /tmp/locker.apk > /dev/null 2>&1; then
    echo "The hosted wrapper must reject unknown flow scopes" >&2
    exit 1
fi
if [[ -e "$temp_dir/invalid.log" ]]; then
    echo "An invalid hosted scope reached the seeded runner" >&2
    exit 1
fi

for selected_flow in all view-collection-and-item-action-menus; do
    override_log="$temp_dir/override-$selected_flow.log"
    if LOCKER_HOSTED_TEST_LOG="$override_log" \
        LOCKER_SEEDED_RUNNER="$temp_dir/runner" \
        LOCKER_SELECTED_FLOW="$selected_flow" \
            "$hosted_runner" \
                --only-flow rename-and-delete-collections \
                --apk /tmp/locker.apk > /dev/null 2>&1; then
        echo "The hosted wrapper must reject caller-supplied --only-flow in $selected_flow mode" >&2
        exit 1
    fi
    if [[ -e "$override_log" ]]; then
        echo "A caller-supplied --only-flow reached the seeded runner in $selected_flow mode" >&2
        exit 1
    fi
done

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'exit 23' \
    > "$temp_dir/failing-runner"
chmod +x "$temp_dir/failing-runner"

if LOCKER_SEEDED_RUNNER="$temp_dir/failing-runner" \
    LOCKER_SELECTED_FLOW=view-collection-and-item-action-menus \
        "$hosted_runner" --apk /tmp/locker.apk; then
    echo "The hosted wrapper must propagate the seeded runner failure" >&2
    exit 1
else
    status=$?
fi
if [[ "$status" -ne 23 ]]; then
    echo "Expected hosted wrapper status 23, got $status" >&2
    exit 1
fi

echo "Locker hosted seeded wrapper tests passed"
