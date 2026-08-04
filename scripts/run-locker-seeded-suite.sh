#!/usr/bin/env bash

set -euo pipefail

umask 077

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly endpoint="${LOCKER_MUSEUM_ENDPOINT:-http://127.0.0.1:8080}"
readonly catalog="$workspace_root/locker/catalog.v1.json"
readonly flow_registry="$workspace_root/locker/product-flows.v1.json"
readonly login_flow="$workspace_root/maestro/locker/online/subflows/login-online-account.yaml"

usage() {
    cat <<'EOF'
Usage: scripts/run-locker-seeded-suite.sh --apk <path> [options]

Run the audited online Locker lane on one account and one Android device. The
account starts empty, one shared fixture is applied once after the empty-state
flow, and all later product flows reuse that backend state. Login and product
behavior remain separate Maestro invocations. The Android device must be a
rootable emulator so the local Museum endpoint can be restored after app-data
clears.

Options:
  --apk <path>          Exact Locker APK to install once (required).
  --seeder <path>       locker-seed executable. Defaults to LOCKER_SEED_BIN or
                        builds the workspace debug binary.
  --maestro <path>      Maestro executable. Defaults to MAESTRO_BIN or maestro.
  --serial <serial>     adb serial. Defaults to ANDROID_SERIAL or the only device.
  --app-id <id>         Defaults to io.ente.locker.independent.
  --output-dir <path>   New public redacted-output directory. Defaults to
                        LOCKER_SEEDED_OUTPUT_DIR or artifacts/maestro/seeded-proof.
  -h, --help            Show this help.
EOF
}

apk_path=""
seeder_bin="${LOCKER_SEED_BIN:-}"
maestro_bin="${MAESTRO_BIN:-maestro}"
serial="${ANDROID_SERIAL:-}"
app_id="io.ente.locker.independent"
output_dir="${LOCKER_SEEDED_OUTPUT_DIR:-$workspace_root/artifacts/maestro/seeded-proof}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)
            apk_path="${2:?--apk requires a path}"
            shift 2
            ;;
        --seeder)
            seeder_bin="${2:?--seeder requires a path}"
            shift 2
            ;;
        --maestro)
            maestro_bin="${2:?--maestro requires a path}"
            shift 2
            ;;
        --serial)
            serial="${2:?--serial requires a serial}"
            shift 2
            ;;
        --app-id)
            app_id="${2:?--app-id requires an application ID}"
            shift 2
            ;;
        --output-dir)
            output_dir="${2:?--output-dir requires a path}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z "$apk_path" || ! -f "$apk_path" ]]; then
    printf 'An existing --apk path is required\n' >&2
    exit 2
fi
if [[ "$endpoint" != "http://127.0.0.1:8080" ]]; then
    printf 'The seeded suite requires http://127.0.0.1:8080 with adb reverse\n' >&2
    exit 2
fi
if [[ "$app_id" != "io.ente.locker.independent" && "$app_id" != "io.ente.locker.dev" ]]; then
    printf 'Unsupported Locker application ID: %s\n' "$app_id" >&2
    exit 2
fi
if [[ -e "$output_dir" ]]; then
    printf 'Output directory must not already exist: %s\n' "$output_dir" >&2
    exit 2
fi

for command in adb docker jq ruby; do
    if ! command -v "$command" > /dev/null; then
        printf 'Required command is not available: %s\n' "$command" >&2
        exit 2
    fi
done
if ! "$maestro_bin" --version > /dev/null; then
    printf 'Maestro executable is not runnable: %s\n' "$maestro_bin" >&2
    exit 2
fi

if [[ -z "$serial" ]]; then
    devices=()
    while IFS= read -r device; do
        devices+=("$device")
    done < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
    if [[ ${#devices[@]} -ne 1 ]]; then
        printf 'Set --serial or ANDROID_SERIAL when zero or multiple devices are attached\n' >&2
        exit 2
    fi
    serial=${devices[0]}
fi
if [[ "$(adb -s "$serial" get-state)" != "device" ]]; then
    printf 'adb device is not ready: %s\n' "$serial" >&2
    exit 2
fi

if [[ -z "$seeder_bin" ]]; then
    if ! command -v cargo > /dev/null; then
        printf 'Required command is not available: cargo\n' >&2
        exit 2
    fi
    seeder_bin="$workspace_root/tools/locker-seed/target/debug/locker-seed"
    cargo build --quiet --locked --manifest-path "$workspace_root/tools/locker-seed/Cargo.toml"
fi
if [[ ! -x "$seeder_bin" ]]; then
    printf 'locker-seed executable is not runnable: %s\n' "$seeder_bin" >&2
    exit 2
fi

private_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
private_parent="${private_parent%/}"
[[ -n "$private_parent" ]] || private_parent=/
readonly private_parent
readonly private_root="$(mktemp -d "${private_parent%/}/locker-seeded-suite.XXXXXX")"
readonly private_nonce="${private_root##*.}"
compose_project="${LOCKER_COMPOSE_PROJECT:-ente-locker-seeded-${PPID}-$(printf '%s' "$private_nonce" | tr '[:upper:]' '[:lower:]')}"
if [[ ! "$compose_project" =~ ^ente-locker-seeded-[a-z0-9-]+$ ]]; then
    printf 'Invalid dedicated Compose project name\n' >&2
    rm -rf -- "$private_root"
    exit 2
fi
readonly compose_project
readonly account_context="$private_root/account-context.json"
readonly private_logs="$private_root/logs"
readonly private_runs="$private_root/runs"
readonly private_maestro="$private_root/maestro"
readonly results_dir="$output_dir/results"
readonly summary_file="$output_dir/summary.txt"

stack_requested=false
cleanup_started=false
output_owned=false
current_phase=initialization

remove_private_root() {
    case "$private_root" in
        "${private_parent%/}"/locker-seeded-suite.*)
            rm -rf -- "$private_root"
            ;;
        *)
            printf 'Refusing to remove an unexpected private suite path\n' >&2
            return 1
            ;;
    esac
}

clear_app_data() {
    local clear_output
    adb -s "$serial" shell am force-stop "$app_id" > /dev/null
    clear_output=$(adb -s "$serial" shell pm clear "$app_id" | tr -d '\r')
    if [[ "$clear_output" != "Success" ]]; then
        printf 'Locker app-data clearing failed\n' >&2
        return 1
    fi
    adb -s "$serial" wait-for-device > /dev/null
}

require_rootable_emulator() {
    adb -s "$serial" root > /dev/null
    adb -s "$serial" wait-for-device > /dev/null
    if [[ "$(adb -s "$serial" shell id -u | tr -d '\r')" != "0" ]]; then
        printf 'Seeded Locker logins require a rootable Android emulator\n' >&2
        return 1
    fi
}

prepare_locker_app_data() {
    local app_data_dir app_owner current_user preferences_dir preferences_file

    clear_app_data
    current_user=$(adb -s "$serial" shell am get-current-user | tr -d '\r')
    if [[ ! "$current_user" =~ ^[0-9]+$ ]]; then
        printf 'Unable to determine the Android user: %s\n' "$current_user" >&2
        return 1
    fi
    app_data_dir="/data/user/$current_user/$app_id"
    preferences_dir="$app_data_dir/shared_prefs"
    preferences_file="$preferences_dir/FlutterSharedPreferences.xml"
    app_owner=$(adb -s "$serial" shell stat -c '%u:%g' "$app_data_dir" | tr -d '\r')
    if [[ ! "$app_owner" =~ ^[0-9]+:[0-9]+$ ]]; then
        printf 'Unable to determine the Locker app-data owner: %s\n' "$app_owner" >&2
        return 1
    fi

    adb -s "$serial" shell "mkdir -p '$preferences_dir'"
    adb -s "$serial" shell \
        "printf '%s\\n' '<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"yes\" ?>' '<map>' '    <string name=\"flutter.endpoint\">$endpoint</string>' '</map>' > '$preferences_file'"
    adb -s "$serial" shell chown -R "$app_owner" "$preferences_dir"
    adb -s "$serial" shell chmod 771 "$preferences_dir"
    adb -s "$serial" shell chmod 660 "$preferences_file"
    adb -s "$serial" shell restorecon "$preferences_dir"
    adb -s "$serial" shell restorecon "$preferences_file"
    if ! adb -s "$serial" shell \
        "grep -q '<string name=\"flutter.endpoint\">$endpoint</string>' '$preferences_file'"; then
        printf 'Unable to preseed the Locker Museum endpoint\n' >&2
        return 1
    fi
}

cleanup() {
    local original_status=$?
    local cleanup_status=0

    if [[ "$cleanup_started" == true ]]; then
        return
    fi
    cleanup_started=true
    trap - EXIT INT TERM

    clear_app_data > /dev/null 2>&1 || true
    if [[ "$stack_requested" == true ]]; then
        if ! LOCKER_COMPOSE_PROJECT="$compose_project" \
            "$seeder_bin" stack down --endpoint "$endpoint" \
            > "$private_logs/stack-cleanup.log" 2>&1; then
            printf 'Seeded suite cleanup failed while removing the dedicated stack\n' >&2
            cleanup_status=1
        fi
    fi
    remove_private_root || cleanup_status=1

    if [[ $original_status -ne 0 ]]; then
        printf 'Seeded suite failed during phase=%s\n' "$current_phase" >&2
        exit "$original_status"
    fi
    exit "$cleanup_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$private_logs" "$private_runs" "$private_maestro" "$results_dir"
output_owned=true

scenarios=()
while IFS= read -r scenario; do
    [[ -n "$scenario" ]] && scenarios+=("$scenario")
done < <(jq --exit-status --raw-output '.initialHostedLane.flows[]' "$flow_registry")
if [[ ${#scenarios[@]} -ne 4 ]]; then
    printf 'The audited online lane must contain exactly four flows\n' >&2
    exit 2
fi

declare -a flows=()
for scenario in "${scenarios[@]}"; do
    flow="$workspace_root/maestro/locker/online/$scenario.yaml"
    if [[ ! -f "$flow" ]]; then
        printf 'Missing canonical flow for scenario=%s\n' "$scenario" >&2
        exit 2
    fi
    flows+=("$flow")
done

readonly seed_before_flow="$(jq --exit-status --raw-output '.initialHostedLane.seedBeforeFlow' "$flow_registry")"
readonly manifest_relative="$(jq --exit-status --raw-output '.onlineFixture.manifest' "$catalog")"
readonly manifest="$workspace_root/locker/$manifest_relative"
if [[ ! " ${scenarios[*]} " =~ " $seed_before_flow " ]] || [[ ! -f "$manifest" ]]; then
    printf 'The online lane seed boundary or shared fixture is invalid\n' >&2
    exit 2
fi

if [[ -n "$(docker ps --all --quiet --filter "label=com.docker.compose.project=$compose_project")" ]] ||
    [[ -n "$(docker volume ls --quiet --filter "label=com.docker.compose.project=$compose_project")" ]] ||
    [[ -n "$(docker network ls --quiet --filter "label=com.docker.compose.project=$compose_project")" ]]; then
    printf 'Refusing to reuse Docker resources for the seeded suite\n' >&2
    exit 2
fi

configure_reverse() {
    local reverse_list
    adb -s "$serial" reverse --remove tcp:8080 > /dev/null 2>&1 || true
    adb -s "$serial" reverse --remove tcp:3200 > /dev/null 2>&1 || true
    adb -s "$serial" reverse tcp:8080 tcp:8080 > /dev/null
    adb -s "$serial" reverse tcp:3200 tcp:3200 > /dev/null
    reverse_list=$(adb -s "$serial" reverse --list)
    if ! grep --quiet --extended-regexp 'tcp:8080[[:space:]]+tcp:8080' <<< "$reverse_list" ||
        ! grep --quiet --extended-regexp 'tcp:3200[[:space:]]+tcp:3200' <<< "$reverse_list"; then
        printf 'Required adb reverse mappings are missing\n' >&2
        return 1
    fi
}

run_private_login() {
    local scenario=$1
    local email=$2
    local password=$3
    local login_root="$private_maestro/login-$scenario"
    local args_file="$login_root/maestro.args"
    local status=0
    local failure_label=""
    login_failure_category=none

    mkdir -p "$login_root"
    printf '%s\n' \
        "--udid=$serial" \
        '--no-ansi' \
        "--debug-output=$login_root/debug" \
        "--test-output-dir=$login_root/output" \
        "--env=APP_ID=$app_id" \
        "--env=USER_EMAIL=$email" \
        "--env=USER_PASSWORD=$password" \
        "$login_flow" > "$args_file"
    chmod 600 "$args_file"

    "$maestro_bin" test "@$args_file" > "$login_root/console.log" 2>&1 || status=$?
    if [[ $status -ne 0 ]]; then
        failure_label=$(awk '/\.\.\. FAILED$/ { print; exit }' "$login_root/console.log")
        case "$failure_label" in
            *"Login to existing account"*) login_failure_category=initial-login-screen ;;
            *"Email"*|*"email"*) login_failure_category=email-field ;;
            *"Password"*|*"password"*) login_failure_category=password-field ;;
            *"Add item"*|*"Save to Locker"*) login_failure_category=post-login-readiness ;;
            *) login_failure_category=unclassified ;;
        esac
    fi
    rm -rf -- "$login_root"
    return "$status"
}

run_product_flow() {
    local scenario=$1
    local flow=$2
    local result_file="$results_dir/$scenario.xml"
    local product_root="$private_maestro/product-$scenario"

    mkdir -p "$product_root"
    "$maestro_bin" test \
        --udid "$serial" \
        --no-ansi \
        -e "APP_ID=$app_id" \
        --format JUNIT \
        --output "$result_file" \
        --debug-output "$product_root/debug" \
        --flatten-debug-output \
        "$flow" > "$product_root/console.log" 2>&1
}

current_phase=stack-up
stack_requested=true
LOCKER_COMPOSE_PROJECT="$compose_project" \
    "$seeder_bin" stack up --endpoint "$endpoint" \
    > "$private_logs/stack-up.log" 2>&1

current_phase=create-account
LOCKER_COMPOSE_PROJECT="$compose_project" \
    "$seeder_bin" create-account \
        --label seeded-android-proof \
        --account-context "$account_context" \
        --endpoint "$endpoint" \
        > "$private_logs/create-account.log" 2>&1
if [[ ! -f "$account_context" ]]; then
    printf 'Account creation did not produce a private context\n' >&2
    exit 1
fi

email=$(jq --exit-status --raw-output '.email' "$account_context")
password=$(jq --exit-status --raw-output '.password' "$account_context")
account_user_id=$(jq --exit-status --raw-output '.userId | tostring' "$account_context")
if [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    printf '::add-mask::%s\n' "$email"
    printf '::add-mask::%s\n' "$password"
fi

current_phase=install-apk
adb -s "$serial" uninstall "$app_id" > /dev/null 2>&1 || true
adb -s "$serial" install -r "$apk_path" > "$private_logs/apk-install.log"
require_rootable_emulator
adb -s "$serial" shell settings put system screen_off_timeout 2147483647 > /dev/null

failure_count=0
records_file="$private_root/scenario-records.txt"
: > "$records_file"
online_run_dir="$private_runs/online-fixture"
fixture_applied=false
fixture_apply_count=0
login_ready=true
login_failure_category=none

current_phase=empty-account-login
prepare_locker_app_data
configure_reverse
if ! run_private_login "empty-account" "$email" "$password"; then
    # A clean same-account retry absorbs occasional emulator focus/network
    # startup flakes without changing the account or backend state.
    prepare_locker_app_data
    configure_reverse
    if ! run_private_login "empty-account" "$email" "$password"; then
        login_ready=false
    fi
fi

for index in "${!scenarios[@]}"; do
    scenario=${scenarios[$index]}
    flow=${flows[$index]}
    scenario_status=pass
    failure_phase=none
    failure_category=none

    if [[ "$login_ready" != true ]]; then
        scenario_status=fail
        failure_phase=login
        failure_category=$login_failure_category
    fi

    if [[ "$scenario_status" == "pass" && "$scenario" == "$seed_before_flow" ]]; then
        current_phase=apply-online-fixture
        if ! "$seeder_bin" apply \
            --scenario online-fixture \
            --manifest "$manifest" \
            --run-dir "$online_run_dir" \
            --account-context "$account_context" \
            > "$private_logs/apply-online-fixture.log" 2>&1; then
            printf 'Online fixture apply failed:\n' >&2
            DIAG_EMAIL="$email" DIAG_PASSWORD="$password" ruby -pe '
              gsub(ENV.fetch("DIAG_EMAIL"), "[REDACTED_EMAIL]")
              gsub(ENV.fetch("DIAG_PASSWORD"), "[REDACTED_PASSWORD]")
            ' "$private_logs/apply-online-fixture.log" | tail -n 20 >&2
            exit 1
        fi
        fixture_applied=true
        fixture_apply_count=1

        observed_user_id=$(jq --exit-status --raw-output '.userId | tostring' "$online_run_dir/run.json")
        observed_email=$(jq --exit-status --raw-output '.email' "$online_run_dir/run.json")
        if [[ "$observed_user_id" != "$account_user_id" || "$observed_email" != "$email" ]]; then
            printf 'Account identity changed while applying the online fixture\n' >&2
            exit 1
        fi
        "$seeder_bin" inspect --run-dir "$online_run_dir" > "$private_logs/inspect-online-fixture.json" 2>&1

        current_phase=seeded-account-login
        prepare_locker_app_data
        configure_reverse
        if ! run_private_login "seeded-account" "$email" "$password"; then
            prepare_locker_app_data
            configure_reverse
            if ! run_private_login "seeded-account" "$email" "$password"; then
                login_ready=false
                scenario_status=fail
                failure_phase=login
                failure_category=$login_failure_category
            fi
        fi
    fi

    if [[ "$scenario_status" == "pass" ]] && ! run_product_flow "$scenario" "$flow"; then
        scenario_status=fail
        failure_phase=product
        failure_category=canonical-yaml
    fi
    current_phase="product-$scenario"

    if [[ "$scenario_status" == "fail" ]]; then
        failure_count=$((failure_count + 1))
    fi
    fixture_sha256=none
    if [[ "$fixture_applied" == true ]]; then
        fixture_sha256="$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$manifest")"
    fi
    printf 'scenario=%s status=%s failure_phase=%s failure_category=%s flow_sha256=%s manifest_sha256=%s\n' \
        "$scenario" "$scenario_status" "$failure_phase" "$failure_category" \
        "$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$flow")" \
        "$fixture_sha256" \
        >> "$records_file"
done

current_phase=finalize
suite_status=pass
if [[ $failure_count -ne 0 ]]; then
    suite_status=fail
fi
if [[ "$fixture_applied" == true ]]; then
    if ! "$seeder_bin" finish --run-dir "$online_run_dir" --status "$suite_status" \
        > "$private_logs/finish-online-fixture.json" 2>&1; then
        printf 'Online fixture finalization failed\n' >&2
        exit 1
    fi
fi
clear_app_data
{
    printf 'seeded_suite status=%s accounts_created=1 fixture_applies=%s backend_resets=0 scenarios=%s failures=%s identity_unchanged=true\n' \
        "$suite_status" "$fixture_apply_count" "${#scenarios[@]}" "$failure_count"
    cat "$records_file"
} > "$summary_file"

if grep --recursive --fixed-strings --quiet -- "$email" "$output_dir" ||
    grep --recursive --fixed-strings --quiet -- "$password" "$output_dir"; then
    printf 'Credential leakage detected in public seeded output; output removed\n' >&2
    if [[ "$output_owned" == true ]]; then
        rm -rf -- "$results_dir"
        rm -f -- "$summary_file"
        rmdir -- "$output_dir" 2> /dev/null || true
    fi
    exit 1
fi

printf 'seeded_suite status=%s accounts_created=1 fixture_applies=%s backend_resets=0 scenarios=%s failures=%s identity_unchanged=true\n' \
    "$suite_status" "$fixture_apply_count" "${#scenarios[@]}" "$failure_count"
if [[ "$suite_status" == "fail" ]]; then
    exit 1
fi
