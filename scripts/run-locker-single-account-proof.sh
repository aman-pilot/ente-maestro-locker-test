#!/usr/bin/env bash

set -euo pipefail

umask 077

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly endpoint="${LOCKER_MUSEUM_ENDPOINT:-http://127.0.0.1:8080}"
private_parent="${TMPDIR:-/tmp}"
private_parent="${private_parent%/}"
if [[ -z "$private_parent" ]]; then
    private_parent=/
fi
readonly private_parent
readonly private_root="$(mktemp -d "${private_parent%/}/locker-single-account-proof.XXXXXX")"
readonly private_nonce="${private_root##*.}"
readonly compose_project="ente-locker-proof-${PPID}-$(printf '%s' "$private_nonce" | tr '[:upper:]' '[:lower:]')"
readonly account_context="$private_root/account-context.json"
readonly private_log_dir="$private_root/logs"
readonly private_run_root="$private_root/runs"

stack_requested=false
cleanup_started=false

now_ms() {
    ruby -e 'puts((Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round)'
}

elapsed_ms() {
    local start_ms=$1
    local end_ms
    end_ms=$(now_ms)
    printf '%s\n' "$((end_ms - start_ms))"
}

report_timing() {
    local phase=$1
    local duration_ms=$2
    local scenario=${3:-}

    if [[ -n "$scenario" ]]; then
        printf 'timing phase=%s scenario=%s duration_ms=%s\n' \
            "$phase" "$scenario" "$duration_ms"
    else
        printf 'timing phase=%s duration_ms=%s\n' "$phase" "$duration_ms"
    fi
}

remove_private_root() {
    case "$private_root" in
        "${private_parent%/}"/locker-single-account-proof.*)
            rm -rf -- "$private_root"
            ;;
        *)
            printf 'Refusing to remove an unexpected private proof path\n' >&2
            return 1
            ;;
    esac
}

classify_private_failure() {
    local log_file=$1
    local category=unclassified

    if grep --quiet --fixed-strings 'restored PostgreSQL state differs' "$log_file"; then
        category=postgres_fingerprint_mismatch
    elif grep --quiet --fixed-strings 'PostgreSQL baseline' "$log_file"; then
        category=postgres_baseline_command
    elif grep --quiet --fixed-strings 'MinIO reset' "$log_file"; then
        category=minio_reset_command
    elif grep --quiet --fixed-strings 'MinIO inventory' "$log_file"; then
        category=minio_inventory_command
    elif grep --quiet --fixed-strings 'authenticated user ID' "$log_file"; then
        category=account_identity_mismatch
    elif grep --quiet --fixed-strings 'baseline is not empty' "$log_file"; then
        category=baseline_not_empty
    elif grep --quiet --fixed-strings 'baseline database is missing' "$log_file"; then
        category=baseline_database_missing
    fi
    printf '%s\n' "$category"
}

cleanup() {
    local original_status=$?
    local cleanup_status=0
    local cleanup_start_ms

    if [[ "$cleanup_started" == true ]]; then
        return
    fi
    cleanup_started=true
    trap - EXIT INT TERM
    cleanup_start_ms=$(now_ms)

    if [[ "$stack_requested" == true ]]; then
        if ! LOCKER_COMPOSE_PROJECT="$compose_project" \
            "$seeder_bin" stack reset --endpoint "$endpoint" \
            > "$private_log_dir/stack-cleanup.log" 2>&1; then
            printf 'proof cleanup failed while removing the dedicated Locker stack\n' >&2
            cleanup_status=1
        fi
    fi

    if ! remove_private_root; then
        cleanup_status=1
    fi
    report_timing "cleanup" "$(elapsed_ms "$cleanup_start_ms")"

    if [[ $original_status -ne 0 ]]; then
        exit "$original_status"
    fi
    exit "$cleanup_status"
}

usage() {
    cat <<'EOF'
Usage: scripts/run-locker-single-account-proof.sh [--seeder <path>]

Prove that four representative Locker fixture profiles can be applied to one
synthetic account, with a verified account reset between profiles.

Options:
  --seeder <path>  locker-seed executable. Defaults to LOCKER_SEED_BIN or the
                   workspace debug binary (built with Cargo when necessary).
  -h, --help       Show this help.
EOF
}

seeder_bin="${LOCKER_SEED_BIN:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --seeder)
            seeder_bin="${2:?--seeder requires a path}"
            shift 2
            ;;
        -h|--help)
            usage
            remove_private_root
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            remove_private_root
            exit 2
            ;;
    esac
done

if [[ "$endpoint" != "http://127.0.0.1:8080" ]]; then
    printf 'The single-account proof requires the dedicated loopback endpoint http://127.0.0.1:8080\n' >&2
    remove_private_root
    exit 2
fi

for command in docker jq ruby; do
    if ! command -v "$command" > /dev/null; then
        printf 'Required command is not available: %s\n' "$command" >&2
        remove_private_root
        exit 2
    fi
done

if [[ -z "$seeder_bin" ]]; then
    if ! command -v cargo > /dev/null; then
        printf 'Required command is not available: cargo\n' >&2
        remove_private_root
        exit 2
    fi
    seeder_bin="$workspace_root/tools/locker-seed/target/debug/locker-seed"
    if ! cargo build \
        --quiet \
        --locked \
        --manifest-path "$workspace_root/tools/locker-seed/Cargo.toml"; then
        remove_private_root
        exit 1
    fi
fi

if [[ ! -x "$seeder_bin" ]]; then
    printf 'locker-seed executable is not runnable\n' >&2
    remove_private_root
    exit 2
fi

mkdir -p "$private_log_dir" "$private_run_root"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

manifest_names=(
    search-note-secret-and-thing
    document
    trash
    add-item-to-multiple-collections
)

for scenario in "${manifest_names[@]}"; do
    manifest="$workspace_root/locker/manifests/$scenario.json"
    if [[ ! -f "$manifest" ]]; then
        printf 'Required proof manifest is missing: %s.json\n' "$scenario" >&2
        exit 2
    fi
done

if [[ -n "$(docker ps --all --quiet --filter "label=com.docker.compose.project=$compose_project")" ]] ||
    [[ -n "$(docker volume ls --quiet --filter "label=com.docker.compose.project=$compose_project")" ]] ||
    [[ -n "$(docker network ls --quiet --filter "label=com.docker.compose.project=$compose_project")" ]]; then
    printf 'Refusing to use a Compose project that already owns Docker resources\n' >&2
    exit 2
fi

stack_requested=true
step_start_ms=$(now_ms)
LOCKER_COMPOSE_PROJECT="$compose_project" \
    "$seeder_bin" stack up --endpoint "$endpoint" \
    > "$private_log_dir/stack-up.log" 2>&1
report_timing "stack_startup" "$(elapsed_ms "$step_start_ms")"

step_start_ms=$(now_ms)
LOCKER_COMPOSE_PROJECT="$compose_project" \
    "$seeder_bin" create-account \
        --label "single-account-proof" \
        --account-context "$account_context" \
        --endpoint "$endpoint" \
        > "$private_log_dir/create-account.log" 2>&1
report_timing "account_creation" "$(elapsed_ms "$step_start_ms")"

if [[ ! -f "$account_context" ]]; then
    printf 'Account creation did not produce a private account context\n' >&2
    exit 1
fi

baseline_email=$(jq --exit-status --raw-output '.email | select(type == "string" and length > 0)' "$account_context" 2>> "$private_log_dir/jq-errors.log")
baseline_user_id=$(jq --exit-status --raw-output '.userId | select(type == "number") | tostring' "$account_context" 2>> "$private_log_dir/jq-errors.log")
printf 'account_identity email=[REDACTED] user_id=%s\n' \
    '[REDACTED]'

step_start_ms=$(now_ms)
LOCKER_COMPOSE_PROJECT="$compose_project" \
    "$seeder_bin" baseline capture --account-context "$account_context" \
    > "$private_log_dir/baseline-capture.json" 2>&1
report_timing "baseline_capture" "$(elapsed_ms "$step_start_ms")"
baseline_identity=$(jq --exit-status --raw-output \
    '.identity | select(type == "string" and startswith("sha256:"))' \
    "$private_log_dir/baseline-capture.json" 2>> "$private_log_dir/jq-errors.log")
jq --exit-status \
    '.collectionRecordCount == 0 and .trashRecordCount == 0 and .bucketObjectCount == 0' \
    "$private_log_dir/baseline-capture.json" > /dev/null 2>> "$private_log_dir/jq-errors.log"

for index in "${!manifest_names[@]}"; do
    scenario=${manifest_names[$index]}
    manifest="$workspace_root/locker/manifests/$scenario.json"
    run_dir="$private_run_root/$scenario"

    step_start_ms=$(now_ms)
    "$seeder_bin" apply \
        --scenario "$scenario" \
        --manifest "$manifest" \
        --run-dir "$run_dir" \
        --account-context "$account_context" \
        > "$private_log_dir/apply-$scenario.log" 2>&1
    report_timing "apply_verify" "$(elapsed_ms "$step_start_ms")" "$scenario"

    run_record="$run_dir/run.json"
    if [[ ! -f "$run_record" ]]; then
        printf 'Seeder did not produce a private run record for scenario=%s\n' "$scenario" >&2
        exit 1
    fi

    observed_email=$(jq --exit-status --raw-output '.email | select(type == "string" and length > 0)' "$run_record" 2>> "$private_log_dir/jq-errors.log")
    observed_user_id=$(jq --exit-status --raw-output \
        '.userId | select(type == "number" or type == "string") | tostring | select(length > 0)' \
        "$run_record" 2>> "$private_log_dir/jq-errors.log")
    if [[ "$observed_email" != "$baseline_email" ]]; then
        printf 'Account email changed while applying scenario=%s\n' "$scenario" >&2
        exit 1
    fi
    if [[ "$observed_user_id" != "$baseline_user_id" ]]; then
        printf 'Account user ID changed while applying scenario=%s\n' "$scenario" >&2
        exit 1
    fi
    printf 'account_identity scenario=%s unchanged=true email=[REDACTED] user_id=[REDACTED]\n' "$scenario"

    step_start_ms=$(now_ms)
    "$seeder_bin" inspect --run-dir "$run_dir" \
        > "$private_log_dir/inspect-$scenario.log" 2>&1
    report_timing "inspection" "$(elapsed_ms "$step_start_ms")" "$scenario"

    if [[ $index -lt $((${#manifest_names[@]} - 1)) ]]; then
        step_start_ms=$(now_ms)
        if ! LOCKER_COMPOSE_PROJECT="$compose_project" \
            "$seeder_bin" reset --account-context "$account_context" \
            > "$private_log_dir/reset-$scenario.log" 2>&1; then
            printf 'Account reset failed for scenario=%s category=%s\n' \
                "$scenario" \
                "$(classify_private_failure "$private_log_dir/reset-$scenario.log")" >&2
            exit 1
        fi
        report_timing "reset" "$(elapsed_ms "$step_start_ms")" "$scenario"
        reset_identity=$(jq --exit-status --raw-output '.identity' "$private_log_dir/reset-$scenario.log" 2>> "$private_log_dir/jq-errors.log")
        if [[ "$reset_identity" != "$baseline_identity" ]]; then
            printf 'Redacted account identity changed while resetting scenario=%s\n' "$scenario" >&2
            exit 1
        fi
        jq --exit-status \
            '.databaseRestored == true and .collectionRecordCount == 0 and .trashRecordCount == 0 and .bucketObjectCount == 0' \
            "$private_log_dir/reset-$scenario.log" > /dev/null 2>> "$private_log_dir/jq-errors.log"
    fi
done

printf 'single_account_proof status=pass accounts_created=1 manifests_verified=%s identity_unchanged=true\n' \
    "${#manifest_names[@]}"
