#!/usr/bin/env bash

set -euo pipefail

umask 077

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly endpoint="${LOCKER_MUSEUM_ENDPOINT:-http://127.0.0.1:8080}"
readonly catalog="$workspace_root/locker/catalog.v1.json"
readonly flow_registry="$workspace_root/locker/product-flows.v1.json"
readonly login_flow="$workspace_root/maestro/locker/online/subflows/login-online-account.yaml"
readonly hierarchy_summarizer="$workspace_root/scripts/summarize-locker-ui-hierarchy.rb"
readonly expected_maestro_version=2.6.1
readonly client_sync_attempts="${LOCKER_CLIENT_SYNC_ATTEMPTS:-90}"
readonly hierarchy_timeout_seconds="${LOCKER_HIERARCHY_TIMEOUT_SECONDS:-15}"

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
  --only-flow <name>    Targeted mode: run one registered product flow.
                        Non-empty flows still get the combined fixture first.
  --seeder <path>       locker-seed executable. Defaults to LOCKER_SEED_BIN or
                        builds the workspace debug binary.
  --maestro <path>      Maestro executable. Defaults to MAESTRO_BIN or maestro.
  --serial <serial>     adb serial. Defaults to ANDROID_SERIAL or the only device.
  --app-id <id>         Defaults to io.ente.locker.independent.
  --output-dir <path>   New public redacted-output directory. Defaults to
                        LOCKER_ONLINE_OUTPUT_DIR or artifacts/maestro/online.
  -h, --help            Show this help.
EOF
}

apk_path=""
only_flow=""
seeder_bin="${LOCKER_SEED_BIN:-}"
maestro_bin="${MAESTRO_BIN:-maestro}"
serial="${ANDROID_SERIAL:-}"
app_id="io.ente.locker.independent"
output_dir="${LOCKER_ONLINE_OUTPUT_DIR:-$workspace_root/artifacts/maestro/online}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apk)
            apk_path="${2:?--apk requires a path}"
            shift 2
            ;;
        --only-flow)
            only_flow="${2:?--only-flow requires a scenario name}"
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
if [[ ! "$client_sync_attempts" =~ ^[1-9][0-9]*$ ]]; then
    printf 'LOCKER_CLIENT_SYNC_ATTEMPTS must be a positive integer\n' >&2
    exit 2
fi
for command in adb docker jq ruby; do
    if ! command -v "$command" > /dev/null; then
        printf 'Required command is not available: %s\n' "$command" >&2
        exit 2
    fi
done
output_dir=$(ruby -e 'puts File.expand_path(ARGV.fetch(0))' "$output_dir")
if [[ -e "$output_dir" ]]; then
    printf 'Output directory must not already exist: %s\n' "$output_dir" >&2
    exit 2
fi
if [[ ! "$hierarchy_timeout_seconds" =~ ^[1-9][0-9]*$ ]] ||
    ((hierarchy_timeout_seconds > 30)); then
    printf 'LOCKER_HIERARCHY_TIMEOUT_SECONDS must be between 1 and 30\n' >&2
    exit 2
fi
if ! maestro_version=$("$maestro_bin" --version); then
    printf 'Maestro executable is not runnable: %s\n' "$maestro_bin" >&2
    exit 2
fi
if [[ "$maestro_version" != "$expected_maestro_version" ]]; then
    printf 'Expected Maestro %s, found %s\n' "$expected_maestro_version" "$maestro_version" >&2
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
readonly diagnostics_dir="$output_dir/diagnostics"
readonly summary_file="$output_dir/summary.txt"

stack_requested=false
cleanup_started=false
output_root_created=false
public_output_verified=false
current_phase=initialization
suite_status=unknown
failed_scenario=none
failed_phase=none
failed_category=none

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

remove_public_output() {
    if [[ "$output_root_created" != true || -z "$output_dir" || "$output_dir" == / ]]; then
        printf 'Refusing to remove an unexpected public output path\n' >&2
        return 1
    fi
    rm -rf -- "$results_dir" "$diagnostics_dir"
    rm -f -- "$summary_file"
    rmdir "$output_dir" 2> /dev/null || true
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
    if [[ -z "$(adb -s "$serial" shell 'command -v sqlite3' | tr -d '\r')" ]]; then
        printf 'Seeded Locker readiness checks require sqlite3 on the emulator\n' >&2
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
    if [[ "$output_root_created" == true && "$public_output_verified" != true ]]; then
        remove_public_output || cleanup_status=1
    fi
    remove_private_root || cleanup_status=1

    if [[ $original_status -ne 0 ]]; then
        if [[ "$public_output_verified" == true && "$suite_status" == fail && "$failed_scenario" != none ]]; then
            printf 'Seeded suite reported verified failure scenario=%s failure_phase=%s failure_category=%s\n' \
                "$failed_scenario" "$failed_phase" "$failed_category" >&2
        else
            printf 'Seeded suite infrastructure failed during phase=%s\n' "$current_phase" >&2
        fi
        exit "$original_status"
    fi
    exit "$cleanup_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$(dirname "$output_dir")"
if ! mkdir "$output_dir"; then
    printf 'Unable to create new public output directory: %s\n' "$output_dir" >&2
    exit 2
fi
output_root_created=true
mkdir -p "$private_logs" "$private_runs" "$private_maestro" "$results_dir"

registered_scenarios=()
while IFS= read -r scenario; do
    [[ -n "$scenario" ]] && registered_scenarios+=("$scenario")
done < <(jq --exit-status --raw-output '.hostedLane.flows[]' "$flow_registry")
if [[ ${#registered_scenarios[@]} -ne 21 ]]; then
    printf 'The audited online lane must contain all 21 proven hosted flows\n' >&2
    exit 2
fi

scenarios=("${registered_scenarios[@]}")
if [[ -n "$only_flow" ]]; then
    if ! jq --exit-status --arg flow "$only_flow" '
        [
          .classifications.hostedCandidate[],
          (.classifications.hostedUnresolved | keys[])
        ]
        | index($flow) != null
      ' "$flow_registry" > /dev/null; then
        printf 'Unknown registered Locker flow: %s\n' "$only_flow" >&2
        exit 2
    fi
    scenarios=("$only_flow")
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

registry_seed_before_flow="$(jq --exit-status --raw-output '.hostedLane.seedBeforeFlow' "$flow_registry")"
seed_before_flow="$registry_seed_before_flow"
if [[ -n "$only_flow" && "$only_flow" != "empty-home-and-save-options" && "$only_flow" != "empty-trash" ]]; then
    seed_before_flow="$only_flow"
fi
readonly registry_seed_before_flow seed_before_flow
readonly manifest_relative="$(jq --exit-status --raw-output '.onlineFixture.manifest' "$catalog")"
readonly manifest="$workspace_root/locker/$manifest_relative"
if [[ ! " ${scenarios[*]} " =~ " $seed_before_flow " ]] || [[ ! -f "$manifest" ]]; then
    if [[ -n "$only_flow" && ( "$only_flow" == "empty-home-and-save-options" || "$only_flow" == "empty-trash" ) && -f "$manifest" ]]; then
        :
    else
        printf 'The online lane seed boundary or shared fixture is invalid\n' >&2
        exit 2
    fi
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
            *"Search your documents"*|*"Add item"*|*"Save to Locker"*) login_failure_category=post-login-readiness ;;
            *) login_failure_category=unclassified ;;
        esac
    fi
    rm -rf -- "$login_root"
    return "$status"
}

wait_for_seeded_client_fixture() {
    local attempt current_user database_path expected_item_ids observed_item_ids=""
    local readiness_log="$private_logs/seeded-client-readiness.log"

    expected_item_ids=$(jq --exit-status --raw-output \
        '.items | to_entries | map(.value) | sort | map(tostring) | join(",")' \
        "$online_run_dir/run.json")
    if [[ -z "$expected_item_ids" ]]; then
        printf 'The seeded run record does not contain client fixture IDs\n' >&2
        return 1
    fi

    current_user=$(adb -s "$serial" shell am get-current-user | tr -d '\r')
    if [[ ! "$current_user" =~ ^[0-9]+$ ]]; then
        printf 'Unable to determine the Android user while checking seeded client state\n' >&2
        return 1
    fi
    database_path="/data/user/$current_user/$app_id/app_flutter/locker.db"

    for ((attempt = 1; attempt <= client_sync_attempts; attempt++)); do
        observed_item_ids=$(
            adb -s "$serial" shell \
                "sqlite3 '$database_path' \"SELECT group_concat(uploaded_file_id, ',') FROM (SELECT uploaded_file_id FROM files ORDER BY uploaded_file_id);\"" \
                2> /dev/null | tr -d '\r'
        ) || observed_item_ids=""
        if [[ "$observed_item_ids" == "$expected_item_ids" ]]; then
            printf 'seeded_client_ready=true items=%s attempts=%s\n' \
                "$(tr ',' '\n' <<< "$observed_item_ids" | wc -l | tr -d ' ')" \
                "$attempt" > "$readiness_log"
            # The published RC can render Home before its initial collection sync
            # finishes and miss the update event. Once the complete fixture is in
            # the client database, restart the process so Home reads that durable
            # state before any product flow begins.
            adb -s "$serial" shell am force-stop "$app_id" > /dev/null
            return 0
        fi
        sleep 1
    done

    printf 'seeded_client_ready=false expected_items=%s observed_items=%s attempts=%s\n' \
        "$(tr ',' '\n' <<< "$expected_item_ids" | wc -l | tr -d ' ')" \
        "$(tr ',' '\n' <<< "${observed_item_ids:-}" | sed '/^$/d' | wc -l | tr -d ' ')" \
        "$client_sync_attempts" > "$readiness_log"
    login_failure_category=seeded-client-sync
    return 1
}

prepare_seeded_client() {
    local scenario=$1
    local email=$2
    local password=$3

    run_private_login "$scenario" "$email" "$password" &&
        wait_for_seeded_client_fixture
}

run_product_flow_once() {
    local scenario=$1
    local flow=$2
    local result_file="$results_dir/$scenario.xml"
    local product_root="$private_maestro/product-$scenario"

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

is_maestro_driver_startup_failure() {
    local result_file=$1

    [[ -f "$result_file" ]] &&
        grep --fixed-strings --quiet 'io.grpc.StatusRuntimeException: UNAVAILABLE' "$result_file" &&
        grep --fixed-strings --quiet 'MaestroDriverBlockingStub.deviceInfo' "$result_file" &&
        grep --fixed-strings --quiet 'Command failed (tcp:' "$result_file"
}

run_product_flow() {
    local scenario=$1
    local flow=$2
    local result_file="$results_dir/$scenario.xml"
    local product_root="$private_maestro/product-$scenario"

    mkdir -p "$product_root"
    if run_product_flow_once "$scenario" "$flow"; then
        return 0
    fi
    if ! is_maestro_driver_startup_failure "$result_file"; then
        return 1
    fi

    product_driver_retries=$((product_driver_retries + 1))
    mv "$product_root/console.log" "$product_root/driver-startup-failure.log"
    rm -rf -- "$product_root/debug"
    rm -f -- "$result_file"
    adb -s "$serial" wait-for-device > /dev/null

    if run_product_flow_once "$scenario" "$flow"; then
        return 0
    fi
    if is_maestro_driver_startup_failure "$result_file"; then
        product_failure_category=maestro-driver-unavailable
    fi
    return 1
}

capture_product_failure_diagnostic() {
    local scenario=$1
    local raw_hierarchy="$private_root/$scenario-ui.csv"
    local hierarchy_log="$private_logs/$scenario-hierarchy.log"
    local hierarchy_status=0
    local public_temp

    mkdir -p "$diagnostics_dir"
    public_temp="$diagnostics_dir/.$scenario-ui.tmp"

    ruby -rtimeout -e '
      timeout_seconds, stdout_path, stderr_path, *command = ARGV
      File.open(stdout_path, "w", 0o600) do |stdout|
        File.open(stderr_path, "w", 0o600) do |stderr|
          pid = Process.spawn(*command, out: stdout, err: stderr, pgroup: true)
          begin
            Timeout.timeout(Integer(timeout_seconds)) { Process.wait(pid) }
            exit($?.exitstatus || 1)
          rescue Timeout::Error
            Process.kill("TERM", -pid) rescue Errno::ESRCH
            sleep 0.2
            Process.kill("KILL", -pid) rescue Errno::ESRCH
            Process.wait(pid) rescue Errno::ECHILD
            exit 124
          end
        end
      end
    ' "$hierarchy_timeout_seconds" "$raw_hierarchy" "$hierarchy_log" \
        "$maestro_bin" --device "$serial" hierarchy \
            --compact --no-ansi --no-reinstall-driver || hierarchy_status=$?
    if [[ $hierarchy_status -ne 0 ]]; then
        rm -f -- "$raw_hierarchy"
        if [[ $hierarchy_status -eq 124 ]]; then
            printf '%s\n' \
                'capture_status=timeout route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
                > "$public_temp"
        else
            printf '%s\n' \
                'capture_status=hierarchy_failed route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
                > "$public_temp"
        fi
        chmod 600 "$public_temp"
        mv "$public_temp" "$diagnostics_dir/$scenario-ui.txt"
        return 0
    fi

    if ruby "$hierarchy_summarizer" "$raw_hierarchy" > "$public_temp" 2>> "$hierarchy_log"; then
        chmod 600 "$public_temp"
        mv "$public_temp" "$diagnostics_dir/$scenario-ui.txt"
    else
        printf '%s\n' \
            'capture_status=parse_failed route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
            > "$public_temp"
        chmod 600 "$public_temp"
        mv "$public_temp" "$diagnostics_dir/$scenario-ui.txt"
    fi
    rm -f -- "$raw_hierarchy"
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
attempted_count=0
product_driver_retries=0
records_file="$private_root/scenario-records.txt"
: > "$records_file"
online_run_dir="$private_runs/online-fixture"
fixture_applied=false
fixture_apply_count=0
fixture_sha256=none
login_ready=true
login_failure_category=none
empty_login_attempts=0
seeded_login_attempts=0

requires_empty_login=true
if [[ -n "$only_flow" && "$only_flow" != "empty-home-and-save-options" && "$only_flow" != "empty-trash" ]]; then
    requires_empty_login=false
fi

if [[ "$requires_empty_login" == true ]]; then
    current_phase=empty-account-login
    prepare_locker_app_data
    configure_reverse
    empty_login_attempts=$((empty_login_attempts + 1))
    if ! run_private_login "empty-account" "$email" "$password"; then
        # A clean same-account retry absorbs occasional emulator focus/network
        # startup flakes without changing the account or backend state.
        prepare_locker_app_data
        configure_reverse
        empty_login_attempts=$((empty_login_attempts + 1))
        if ! run_private_login "empty-account" "$email" "$password"; then
            login_ready=false
        fi
    fi
fi

for index in "${!scenarios[@]}"; do
    scenario=${scenarios[$index]}
    flow=${flows[$index]}
    attempted_count=$((attempted_count + 1))
    scenario_status=pass
    failure_phase=none
    failure_category=none
    product_failure_category=canonical-yaml

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
        fixture_sha256="$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$manifest")"

        observed_user_id=$(jq --exit-status --raw-output '.userId | tostring' "$online_run_dir/run.json")
        observed_email=$(jq --exit-status --raw-output '.email' "$online_run_dir/run.json")
        if [[ "$observed_user_id" != "$account_user_id" || "$observed_email" != "$email" ]]; then
            printf 'Account identity changed while applying the online fixture\n' >&2
            exit 1
        fi
        current_phase=seeded-account-login
        prepare_locker_app_data
        configure_reverse
        seeded_login_attempts=$((seeded_login_attempts + 1))
        if ! prepare_seeded_client "seeded-account" "$email" "$password"; then
            prepare_locker_app_data
            configure_reverse
            seeded_login_attempts=$((seeded_login_attempts + 1))
            if ! prepare_seeded_client "seeded-account" "$email" "$password"; then
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
        failure_category=$product_failure_category
        capture_product_failure_diagnostic "$scenario" || true
    fi
    current_phase="product-$scenario"

    if [[ "$scenario_status" == "fail" ]]; then
        failure_count=$((failure_count + 1))
        failed_scenario=$scenario
        failed_phase=$failure_phase
        failed_category=$failure_category
    fi
    printf 'scenario=%s status=%s failure_phase=%s failure_category=%s flow_sha256=%s manifest_sha256=%s\n' \
        "$scenario" "$scenario_status" "$failure_phase" "$failure_category" \
        "$(ruby -rdigest -e 'puts Digest::SHA256.file(ARGV.fetch(0)).hexdigest' "$flow")" \
        "$fixture_sha256" \
        >> "$records_file"

    # The lane intentionally reuses one mutable account. Once a product flow
    # fails, later state is no longer trustworthy, so stop at the first blocker
    # instead of reporting dependent cascade failures.
    if [[ "$scenario_status" == "fail" ]]; then
        break
    fi
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
    printf 'seeded_suite status=%s accounts_created=1 fixture_applies=%s backend_resets=0 scenarios=%s failures=%s identity_unchanged=true empty_login_attempts=%s seeded_login_attempts=%s product_driver_retries=%s\n' \
        "$suite_status" "$fixture_apply_count" "$attempted_count" "$failure_count" \
        "$empty_login_attempts" "$seeded_login_attempts" "$product_driver_retries"
    cat "$records_file"
} > "$summary_file"

credential_found=false
for credential in "$email" "$password"; do
    if grep --recursive --fixed-strings --quiet -- "$credential" "$output_dir"; then
        credential_found=true
        break
    else
        credential_scan_status=$?
        if [[ $credential_scan_status -ne 1 ]]; then
            printf 'Unable to verify public seeded output for credential leakage\n' >&2
            exit 1
        fi
    fi
done
if [[ "$credential_found" == true ]]; then
    printf 'Credential leakage detected in public seeded output; output removed\n' >&2
    remove_public_output
    exit 1
fi
public_output_verified=true

printf 'seeded_suite status=%s accounts_created=1 fixture_applies=%s backend_resets=0 scenarios=%s failures=%s identity_unchanged=true empty_login_attempts=%s seeded_login_attempts=%s product_driver_retries=%s\n' \
    "$suite_status" "$fixture_apply_count" "$attempted_count" "$failure_count" \
    "$empty_login_attempts" "$seeded_login_attempts" "$product_driver_retries"
if [[ "$suite_status" == "fail" ]]; then
    exit 1
fi
