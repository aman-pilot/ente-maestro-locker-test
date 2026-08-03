#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runner="$workspace_root/scripts/run-locker-single-account-proof.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin" "$temp_dir/private" "$temp_dir/state"

cat > "$temp_dir/bin/locker-seed" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

printf '%s|%s\n' "${LOCKER_COMPOSE_PROJECT:-}" "$*" >> "$LOCKER_PROOF_MOCK_LOG"

command_name=${1:?missing command}
shift

value_after() {
    local wanted=$1
    shift
    while [[ $# -gt 0 ]]; do
        if [[ $1 == "$wanted" ]]; then
            printf '%s\n' "${2:?missing value after $wanted}"
            return
        fi
        shift
    done
    return 1
}

case "$command_name" in
    stack)
        exit 0
        ;;
    create-account)
        count=0
        [[ -f "$LOCKER_PROOF_ACCOUNT_COUNT" ]] && count=$(<"$LOCKER_PROOF_ACCOUNT_COUNT")
        count=$((count + 1))
        printf '%s\n' "$count" > "$LOCKER_PROOF_ACCOUNT_COUNT"
        if [[ $count -gt 1 ]]; then
            printf 'create-account was invoked more than once\n' >&2
            exit 91
        fi
        account_context=$(value_after --account-context "$@")
        mkdir -p "$(dirname "$account_context")"
        cat > "$account_context" <<'JSON'
{"version":1,"endpoint":"http://127.0.0.1:8080","email":"proof-private@example.org","password":"proof-private-password","userId":4242}
JSON
        chmod 600 "$account_context"
        ;;
    baseline)
        action=${1:?missing baseline action}
        shift
        [[ "$action" == capture ]]
        value_after --account-context "$@" > /dev/null
        printf '{"identity":"sha256:mock-redacted","collectionRecordCount":0,"trashRecordCount":0,"bucketObjectCount":0}\n'
        ;;
    apply)
        scenario=$(value_after --scenario "$@")
        run_dir=$(value_after --run-dir "$@")
        if [[ $scenario == "${LOCKER_PROOF_FAIL_SCENARIO:-}" ]]; then
            printf 'mock apply failure with proof-private-password\n' >&2
            exit 88
        fi
        mkdir -p "$run_dir"
        cat > "$run_dir/run.json" <<JSON
{"version":1,"scenarioId":"$scenario","endpoint":"http://127.0.0.1:8080","email":"proof-private@example.org","password":"proof-private-password","userId":4242,"createdAtMs":1,"manifestPath":"private","manifestSha256":"private","collections":{},"items":{}}
JSON
        chmod 600 "$run_dir/run.json"
        ;;
    inspect)
        # Deliberately emit credentials: the proof runner must keep all raw
        # seeder output in its private temporary directory.
        printf '{"email":"proof-private@example.org","password":"proof-private-password","userId":4242}\n'
        ;;
    reset)
        value_after --account-context "$@" > /dev/null
        printf '{"identity":"sha256:mock-redacted","collectionRecordCount":0,"trashRecordCount":0,"bucketObjectCount":0,"databaseRestored":true}\n'
        ;;
    *)
        printf 'Unexpected mocked locker-seed command: %s\n' "$command_name" >&2
        exit 2
        ;;
esac
EOF
chmod +x "$temp_dir/bin/locker-seed"
cat > "$temp_dir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# The runner only asks whether its generated Compose project already owns
# resources. Empty output models a new, unused project.
exit 0
EOF
chmod +x "$temp_dir/bin/docker"

output_file="$temp_dir/output.log"
PATH="$temp_dir/bin:$PATH" \
LOCKER_PROOF_MOCK_LOG="$temp_dir/state/commands.log" \
LOCKER_PROOF_ACCOUNT_COUNT="$temp_dir/state/account-count" \
TMPDIR="$temp_dir/private" \
    "$runner" --seeder "$temp_dir/bin/locker-seed" > "$output_file"

[[ "$(<"$temp_dir/state/account-count")" == 1 ]]
[[ "$(grep --count '|create-account ' "$temp_dir/state/commands.log")" == 1 ]]
[[ "$(grep --count '|baseline capture ' "$temp_dir/state/commands.log")" == 1 ]]
[[ "$(grep --count '|apply ' "$temp_dir/state/commands.log")" == 4 ]]
[[ "$(grep --count '|inspect ' "$temp_dir/state/commands.log")" == 4 ]]
[[ "$(grep --count '|reset --account-context ' "$temp_dir/state/commands.log")" == 3 ]]
[[ "$(grep --count '|stack up ' "$temp_dir/state/commands.log")" == 1 ]]
[[ "$(grep --count '|stack reset ' "$temp_dir/state/commands.log")" == 1 ]]

trash_apply_line=$(grep --line-number '|apply --scenario trash ' "$temp_dir/state/commands.log")
trash_apply_line=${trash_apply_line%%:*}
final_apply_line=$(grep --line-number '|apply --scenario add-item-to-multiple-collections ' "$temp_dir/state/commands.log")
final_apply_line=${final_apply_line%%:*}
reset_after_trash_line=$(awk -F: -v trash_line="$trash_apply_line" \
    '$0 ~ /\|reset --account-context / && NR > trash_line { print NR; exit }' \
    "$temp_dir/state/commands.log")
[[ -n "$reset_after_trash_line" ]]
(( trash_apply_line < reset_after_trash_line ))
(( reset_after_trash_line < final_apply_line ))

stack_project=$(awk -F'|' '$2 ~ /^stack up / { print $1 }' "$temp_dir/state/commands.log")
cleanup_project=$(awk -F'|' '$2 ~ /^stack reset / { print $1 }' "$temp_dir/state/commands.log")
[[ -n "$stack_project" ]]
[[ "$stack_project" == "$cleanup_project" ]]
[[ "$stack_project" == ente-locker-proof-* ]]

grep --quiet --fixed-strings 'single_account_proof status=pass accounts_created=1 manifests_verified=4 identity_unchanged=true' "$output_file"
[[ "$(grep --count 'timing phase=apply_verify ' "$output_file")" == 4 ]]
[[ "$(grep --count 'timing phase=inspection ' "$output_file")" == 4 ]]
[[ "$(grep --count 'timing phase=reset ' "$output_file")" == 3 ]]
[[ "$(grep --count 'timing phase=baseline_capture ' "$output_file")" == 1 ]]
[[ "$(grep --count 'timing phase=cleanup ' "$output_file")" == 1 ]]
grep --quiet --fixed-strings 'account_identity scenario=trash unchanged=true email=[REDACTED] user_id=[REDACTED]' "$output_file"

if grep --quiet --extended-regexp \
    'proof-private|example\.org|4242|account-context\.json|locker-single-account-proof\.' \
    "$output_file"; then
    printf 'Proof runner leaked private identity or paths\n' >&2
    exit 1
fi

if find "$temp_dir/private" -mindepth 1 -print -quit | grep --quiet .; then
    printf 'Proof runner left private temporary records behind\n' >&2
    exit 1
fi

rm -f "$temp_dir/state/commands.log" "$temp_dir/state/account-count"
failure_output="$temp_dir/failure-output.log"
if PATH="$temp_dir/bin:$PATH" \
    LOCKER_PROOF_MOCK_LOG="$temp_dir/state/commands.log" \
    LOCKER_PROOF_ACCOUNT_COUNT="$temp_dir/state/account-count" \
    LOCKER_PROOF_FAIL_SCENARIO="document" \
    TMPDIR="$temp_dir/private" \
    "$runner" --seeder "$temp_dir/bin/locker-seed" \
        > "$failure_output" 2>&1; then
    printf 'Expected a failed manifest apply to fail the proof\n' >&2
    exit 1
fi

[[ "$(<"$temp_dir/state/account-count")" == 1 ]]
[[ "$(grep --count '|create-account ' "$temp_dir/state/commands.log")" == 1 ]]
[[ "$(grep --count '|stack reset ' "$temp_dir/state/commands.log")" == 1 ]]
failure_stack_project=$(awk -F'|' '$2 ~ /^stack up / { print $1 }' "$temp_dir/state/commands.log")
failure_cleanup_project=$(awk -F'|' '$2 ~ /^stack reset / { print $1 }' "$temp_dir/state/commands.log")
[[ -n "$failure_stack_project" ]]
[[ "$failure_stack_project" == "$failure_cleanup_project" ]]

if grep --quiet --extended-regexp \
    'proof-private|example\.org|4242|account-context\.json|locker-single-account-proof\.' \
    "$failure_output"; then
    printf 'Failure path leaked private identity, credentials, or paths\n' >&2
    exit 1
fi

if find "$temp_dir/private" -mindepth 1 -print -quit | grep --quiet .; then
    printf 'Failure path left private temporary records behind\n' >&2
    exit 1
fi

remote_output="$temp_dir/remote-output.log"
rm -f "$temp_dir/state/commands.log" "$temp_dir/state/account-count"
if PATH="$temp_dir/bin:$PATH" \
    LOCKER_PROOF_MOCK_LOG="$temp_dir/state/commands.log" \
    LOCKER_PROOF_ACCOUNT_COUNT="$temp_dir/state/account-count" \
    LOCKER_MUSEUM_ENDPOINT="https://museum.example.org" \
    TMPDIR="$temp_dir/private" \
    "$runner" --seeder "$temp_dir/bin/locker-seed" \
        > "$remote_output" 2>&1; then
    printf 'Expected the proof runner to reject a non-loopback endpoint\n' >&2
    exit 1
fi
[[ ! -e "$temp_dir/state/commands.log" ]]
[[ ! -e "$temp_dir/state/account-count" ]]
if find "$temp_dir/private" -mindepth 1 -print -quit | grep --quiet .; then
    printf 'Rejected remote endpoint left private temporary records behind\n' >&2
    exit 1
fi

printf 'Locker single-account proof runner tests passed\n'
