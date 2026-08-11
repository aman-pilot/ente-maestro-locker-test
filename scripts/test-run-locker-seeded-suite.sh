#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runner="$workspace_root/scripts/run-locker-seeded-suite.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin" "$temp_dir/logs"
touch "$temp_dir/locker.apk"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "docker %s\n" "$*" >> "$LOCKER_TEST_LOG/docker.log"' \
    'exit 0' \
    > "$temp_dir/bin/docker"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "adb %s\n" "$*" >> "$LOCKER_TEST_LOG/adb.log"' \
    'case "$*" in' \
    '  *"get-state"*) echo device ;;' \
    '  *"shell id -u"*) echo 0 ;;' \
    '  *"shell command -v sqlite3"*) echo /system/bin/sqlite3 ;;' \
    '  *"shell sqlite3 "*) echo "${LOCKER_TEST_CLIENT_ITEM_IDS:-1,2,3,4,5,6,7,8,9,10,11,12,13}"; echo "adb seeded-db-probe" >> "$LOCKER_EVENT_LOG" ;;' \
    '  *"shell am force-stop"*) echo "adb force-stop" >> "$LOCKER_EVENT_LOG" ;;' \
    '  *"shell am get-current-user"*) echo 0 ;;' \
    '  *"shell stat -c"*) echo 10000:10000 ;;' \
    '  *"shell pm clear"*)' \
    '    if [[ ${LOCKER_TEST_FINAL_CLEAR_FAIL:-false} == true && -f "$LOCKER_TEST_LOG/final-clear-ready" ]]; then echo Failure; else echo Success; fi' \
    '    echo "adb pm-clear" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    '  *"reverse --list"*) printf "emulator-test tcp:8080 tcp:8080\nemulator-test tcp:3200 tcp:3200\n" ;;' \
    '  *"reverse tcp:"*) echo "adb reverse" >> "$LOCKER_EVENT_LOG" ;;' \
    'esac' \
    > "$temp_dir/bin/adb"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then echo 2.6.1; exit 0; fi' \
    'printf "maestro %s\n" "$*" >> "$LOCKER_TEST_LOG/maestro.log"' \
    'if [[ " $* " == *" hierarchy "* ]]; then' \
    '  echo "maestro hierarchy" >> "$LOCKER_EVENT_LOG"' \
    '  if [[ ${LOCKER_TEST_HIERARCHY_FAIL:-false} == true ]]; then exit 1; fi' \
    '  if [[ ${LOCKER_TEST_HIERARCHY_HANG:-false} == true ]]; then sleep 30; fi' \
    '  if [[ ${LOCKER_TEST_HIERARCHY_MALFORMED:-false} == true ]]; then echo malformed; exit 0; fi' \
    '  printf "%s\n" \' \
    '    "element_num,depth,attributes,parent_num" \' \
    '    "0,0,\"bounds=[0,0][1080,2340]; enabled=true\"," \' \
    '    "1,1,\"clickable=true; bounds=[800,180][940,320]; enabled=true\",0" \' \
    '    "2,1,\"text=seeded-android-proof-test@example.org; accessibilityText=Locker-test!Aa1; bounds=[40,400][900,520]\",0"' \
    '  exit 0' \
    'fi' \
    'if [[ ${2:-} == @* ]]; then' \
    '  args_file=${2#@}' \
    '  mode=$(stat -c %a "$args_file" 2>/dev/null || stat -f %Lp "$args_file")' \
    '  [[ "$mode" == 600 ]]' \
    '  grep --quiet --fixed-strings -- "--env=USER_EMAIL=seeded-android-proof-test@example.org" "$args_file"' \
    '  grep --quiet --fixed-strings -- "--env=USER_PASSWORD=Locker-test!Aa1" "$args_file"' \
    '  if grep --quiet --fixed-strings -- "MUSEUM_ENDPOINT" "$args_file"; then exit 1; fi' \
    '  echo "maestro login" >> "$LOCKER_EVENT_LOG"' \
    '  if [[ ${LOCKER_TEST_LOGIN_FAIL:-false} == true ]]; then' \
    '    echo "Assert that Login to existing account is visible ... FAILED"' \
    '    exit 1' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'output=""' \
    'previous=""' \
    'for argument in "$@"; do' \
    '  if [[ "$previous" == --output ]]; then output="$argument"; fi' \
    '  previous="$argument"' \
    'done' \
    'scenario="$(basename "${output%.xml}")"' \
    'echo "maestro product $scenario" >> "$LOCKER_EVENT_LOG"' \
    'mkdir -p "$(dirname "$output")"' \
    'if [[ ${LOCKER_TEST_PRODUCT_DRIVER_FAIL_ALWAYS:-false} == true || ( ${LOCKER_TEST_PRODUCT_DRIVER_FAIL_ONCE:-false} == true && ! -f "$LOCKER_TEST_LOG/product-driver-failed-once" ) ]]; then' \
    '  touch "$LOCKER_TEST_LOG/product-driver-failed-once"' \
    '  printf "<testsuite tests=\"1\" failures=\"1\"><testcase time=\"0.0\"><failure>io.grpc.StatusRuntimeException: UNAVAILABLE MaestroDriverBlockingStub.deviceInfo Command failed (tcp:46359): closed</failure></testcase></testsuite>\n" > "$output"' \
    '  exit 1' \
    'fi' \
    'if [[ ${LOCKER_TEST_PRODUCT_FAIL:-false} == true ]]; then' \
    '  failure_message=${LOCKER_TEST_PRODUCT_FAILURE_MESSAGE:-forced product failure}' \
    '  printf "<testsuite name=\"%s\" tests=\"1\" failures=\"1\"><testcase><failure>%s</failure></testcase></testsuite>\n" "$scenario" "$failure_message" > "$output"' \
    '  exit 1' \
    'fi' \
    'if [[ ${LOCKER_TEST_LEAK:-false} == true && "$scenario" == search-note-secret-and-thing ]]; then' \
    '  printf "<testsuite name=\"seeded-android-proof-test@example.org\"/>\n" > "$output"' \
    'else' \
    '  printf "<testsuite name=\"%s\"/>\n" "$scenario" > "$output"' \
    'fi' \
    > "$temp_dir/bin/maestro"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "seeder %s\n" "$*" >> "$LOCKER_TEST_LOG/seeder.log"' \
    'command_name=${1:-}' \
    'case "$command_name" in' \
    '  stack)' \
    '    echo "seeder stack ${2:-}" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    '  create-account)' \
    '    context=""; previous=""' \
    '    for argument in "$@"; do [[ "$previous" == --account-context ]] && context="$argument"; previous="$argument"; done' \
    '    printf "%s\n" "{\"version\":1,\"endpoint\":\"http://127.0.0.1:8080\",\"email\":\"seeded-android-proof-test@example.org\",\"password\":\"Locker-test!Aa1\",\"userId\":42}" > "$context"' \
    '    chmod 600 "$context"' \
    '    echo "seeder create-account" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    '  apply)' \
    '    run_dir=""; scenario=""; previous=""' \
    '    for argument in "$@"; do' \
    '      [[ "$previous" == --run-dir ]] && run_dir="$argument"' \
    '      [[ "$previous" == --scenario ]] && scenario="$argument"' \
    '      previous="$argument"' \
    '    done' \
    '    mkdir -p "$run_dir"' \
    '    printf "%s\n" "{\"endpoint\":\"http://127.0.0.1:8080\",\"email\":\"seeded-android-proof-test@example.org\",\"password\":\"Locker-test!Aa1\",\"userId\":42,\"items\":{\"item01\":1,\"item02\":2,\"item03\":3,\"item04\":4,\"item05\":5,\"item06\":6,\"item07\":7,\"item08\":8,\"item09\":9,\"item10\":10,\"item11\":11,\"item12\":12,\"item13\":13}}" > "$run_dir/run.json"' \
    '    chmod 600 "$run_dir/run.json"' \
    '    echo "seeder apply $scenario" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    '  finish)' \
    '    run_dir=""; previous=""' \
    '    for argument in "$@"; do [[ "$previous" == --run-dir ]] && run_dir="$argument"; previous="$argument"; done' \
    '    if [[ ${LOCKER_TEST_FINISH_FAIL:-false} == true ]]; then exit 1; fi' \
    '    rm -f "$run_dir/run.json"' \
    '    echo "{}"' \
    '    echo "seeder finish $(basename "$run_dir")" >> "$LOCKER_EVENT_LOG"' \
    '    if [[ ${LOCKER_TEST_FINAL_CLEAR_FAIL:-false} == true ]]; then touch "$LOCKER_TEST_LOG/final-clear-ready"; fi' \
    '    ;;' \
    'esac' \
    > "$temp_dir/bin/locker-seed"

chmod +x "$temp_dir/bin/adb" "$temp_dir/bin/docker" "$temp_dir/bin/locker-seed" "$temp_dir/bin/maestro"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo 2.5.1' \
    > "$temp_dir/bin/wrong-maestro"
chmod +x "$temp_dir/bin/wrong-maestro"

if PATH="$temp_dir/bin:$PATH" \
    LOCKER_SEED_BIN="$temp_dir/bin/locker-seed" \
    "$runner" \
        --apk "$temp_dir/locker.apk" \
        --maestro "$temp_dir/bin/wrong-maestro" \
        --serial emulator-test \
        --output-dir "$temp_dir/wrong-maestro-output" \
        > /dev/null 2>&1; then
    echo "Expected a mismatched Maestro version to fail the seeded runner" >&2
    exit 1
fi

mkdir -p "$temp_dir/existing-output"
touch "$temp_dir/existing-output/user-file"
if PATH="$temp_dir/bin:$PATH" \
    LOCKER_SEED_BIN="$temp_dir/bin/locker-seed" \
    "$runner" \
        --apk "$temp_dir/locker.apk" \
        --maestro "$temp_dir/bin/maestro" \
        --serial emulator-test \
        --output-dir "$temp_dir/missing/../existing-output" \
        > /dev/null 2>&1; then
    echo "Expected an existing normalized output directory to be rejected" >&2
    exit 1
fi
if [[ ! -f "$temp_dir/existing-output/user-file" ]]; then
    echo "The runner removed a caller-owned output file" >&2
    exit 1
fi

run_suite() {
    local output_dir=$1
    shift
    PATH="$temp_dir/bin:$PATH" \
    RUNNER_TEMP="$temp_dir" \
    LOCKER_TEST_LOG="$temp_dir/logs" \
    LOCKER_EVENT_LOG="$temp_dir/logs/events.log" \
    LOCKER_SEED_BIN="$temp_dir/bin/locker-seed" \
    MAESTRO_BIN="$temp_dir/bin/maestro" \
    "$@" \
        "$runner" \
            --apk "$temp_dir/locker.apk" \
            --serial emulator-test \
            --output-dir "$output_dir"
}

run_target_suite() {
    local output_dir=$1
    local flow=$2
    PATH="$temp_dir/bin:$PATH" \
    RUNNER_TEMP="$temp_dir" \
    LOCKER_TEST_LOG="$temp_dir/logs" \
    LOCKER_EVENT_LOG="$temp_dir/logs/events.log" \
    LOCKER_SEED_BIN="$temp_dir/bin/locker-seed" \
    MAESTRO_BIN="$temp_dir/bin/maestro" \
        "$runner" \
            --apk "$temp_dir/locker.apk" \
            --serial emulator-test \
            --only-flow "$flow" \
            --output-dir "$output_dir"
}

output_dir="$temp_dir/public-pass"
run_suite "$output_dir" env

[[ "$(grep -c 'seeder create-account' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder reset$' "$temp_dir/logs/events.log" || true)" -eq 0 ]]
[[ "$(grep -c '^seeder apply online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder finish online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 2 ]]
[[ "$(grep -c '^maestro product ' "$temp_dir/logs/events.log")" -eq 18 ]]
[[ "$(grep -c '^adb reverse$' "$temp_dir/logs/events.log")" -eq 4 ]]
[[ "$(grep -c '^adb seeded-db-probe$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^adb force-stop$' "$temp_dir/logs/events.log")" -eq 5 ]]
[[ "$(grep -c '^adb pm-clear$' "$temp_dir/logs/events.log")" -ge 4 ]]
[[ "$(grep -c 'flutter.endpoint' "$temp_dir/logs/adb.log")" -ge 2 ]]

grep --quiet --fixed-strings \
    'seeded_suite status=pass accounts_created=1 fixture_applies=1 backend_resets=0 scenarios=18 failures=0 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=1' \
    "$output_dir/summary.txt"
[[ "$(find "$output_dir/results" -type f -name '*.xml' | wc -l | tr -d ' ')" -eq 18 ]]
if grep --recursive --quiet --extended-regexp \
    'seeded-android-proof-test@example\.org|Locker-test!Aa1' "$output_dir"; then
    echo "Public seeded output leaked credentials" >&2
    exit 1
fi
if grep --fixed-strings 'USER_EMAIL=' "$temp_dir/logs/maestro.log" > /dev/null ||
    grep --fixed-strings 'USER_PASSWORD=' "$temp_dir/logs/maestro.log" > /dev/null; then
    echo "Credentials escaped the private Maestro response file" >&2
    exit 1
fi
if find "$temp_dir" -maxdepth 1 -type d -name 'locker-seeded-suite.*' | grep --quiet .; then
    echo "Private seeded-suite directory was not removed" >&2
    exit 1
fi

: > "$temp_dir/logs/events.log"
rm -f "$temp_dir/logs/product-driver-failed-once"
driver_retry_output="$temp_dir/public-driver-retry"
run_suite "$driver_retry_output" env LOCKER_TEST_PRODUCT_DRIVER_FAIL_ONCE=true
[[ "$(grep -c '^maestro product empty-home-and-save-options$' "$temp_dir/logs/events.log")" -eq 2 ]]
[[ "$(grep -c '^maestro product ' "$temp_dir/logs/events.log")" -eq 19 ]]
grep --quiet --fixed-strings \
    'scenarios=18 failures=0 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=1 product_driver_retries=1' \
    "$driver_retry_output/summary.txt"
if [[ -d "$driver_retry_output/diagnostics" ]]; then
    echo "A recovered pre-flow Maestro driver failure produced a product diagnostic" >&2
    exit 1
fi

: > "$temp_dir/logs/events.log"
persistent_driver_failure_output="$temp_dir/public-persistent-driver-failure"
if LOCKER_TEST_PRODUCT_DRIVER_FAIL_ALWAYS=true \
    run_target_suite "$persistent_driver_failure_output" empty-home-and-save-options \
    > /dev/null 2>&1; then
    echo "Expected the persistent Maestro driver failure to fail" >&2
    exit 1
fi
[[ "$(grep -c '^maestro product empty-home-and-save-options$' "$temp_dir/logs/events.log")" -eq 2 ]]
grep --quiet --fixed-strings \
    'failure_phase=product failure_category=maestro-driver-unavailable' \
    "$persistent_driver_failure_output/summary.txt"
grep --quiet --fixed-strings \
    'scenarios=1 failures=1 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=0 product_driver_retries=1' \
    "$persistent_driver_failure_output/summary.txt"

: > "$temp_dir/logs/events.log"
target_seeded_output="$temp_dir/public-target-seeded"
run_target_suite "$target_seeded_output" rename-and-delete-collections
[[ "$(grep -c '^seeder create-account$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder apply online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder finish online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^adb seeded-db-probe$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^adb force-stop$' "$temp_dir/logs/events.log")" -eq 4 ]]
[[ "$(grep -c '^maestro product rename-and-delete-collections$' "$temp_dir/logs/events.log")" -eq 1 ]]
grep --quiet --fixed-strings \
    'seeded_suite status=pass accounts_created=1 fixture_applies=1 backend_resets=0 scenarios=1 failures=0 identity_unchanged=true empty_login_attempts=0 seeded_login_attempts=1' \
    "$target_seeded_output/summary.txt"
[[ "$(find "$target_seeded_output/results" -type f -name '*.xml' | wc -l | tr -d ' ')" -eq 1 ]]

: > "$temp_dir/logs/events.log"
target_empty_output="$temp_dir/public-target-empty"
run_target_suite "$target_empty_output" empty-home-and-save-options
[[ "$(grep -c '^seeder create-account$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder apply online-fixture$' "$temp_dir/logs/events.log" || true)" -eq 0 ]]
[[ "$(grep -c '^seeder finish online-fixture$' "$temp_dir/logs/events.log" || true)" -eq 0 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^maestro product empty-home-and-save-options$' "$temp_dir/logs/events.log")" -eq 1 ]]
grep --quiet --fixed-strings \
    'seeded_suite status=pass accounts_created=1 fixture_applies=0 backend_resets=0 scenarios=1 failures=0 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=0' \
    "$target_empty_output/summary.txt"
[[ "$(find "$target_empty_output/results" -type f -name '*.xml' | wc -l | tr -d ' ')" -eq 1 ]]

: > "$temp_dir/logs/events.log"
leak_output="$temp_dir/public-leak"
if run_suite "$leak_output" env LOCKER_TEST_LEAK=true > /dev/null 2>&1; then
    echo "Expected credential leakage to fail the seeded suite" >&2
    exit 1
fi
if [[ -e "$leak_output" ]]; then
    echo "Credential-bearing public output was not removed" >&2
    exit 1
fi

: > "$temp_dir/logs/events.log"
login_failure_output="$temp_dir/public-login-failure"
if run_suite "$login_failure_output" env LOCKER_TEST_LOGIN_FAIL=true > /dev/null 2>&1; then
    echo "Expected private login failure to fail the seeded suite" >&2
    exit 1
fi
[[ "$(grep -c 'failure_phase=login failure_category=initial-login-screen' "$login_failure_output/summary.txt")" -eq 1 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 2 ]]
grep --quiet --fixed-strings \
    'scenarios=1 failures=1 identity_unchanged=true empty_login_attempts=2 seeded_login_attempts=0' \
    "$login_failure_output/summary.txt"
if [[ -d "$login_failure_output/results" ]] && find "$login_failure_output/results" -type f | grep --quiet .; then
    echo "Product JUnit exists even though private login failed" >&2
    exit 1
fi
if [[ -d "$login_failure_output/diagnostics" ]]; then
    echo "A product diagnostic exists even though private login failed" >&2
    exit 1
fi

: > "$temp_dir/logs/events.log"
client_sync_failure_output="$temp_dir/public-client-sync-failure"
if LOCKER_TEST_CLIENT_ITEM_IDS=1,2 LOCKER_CLIENT_SYNC_ATTEMPTS=1 \
    run_target_suite "$client_sync_failure_output" rename-and-delete-collections \
    > /dev/null 2>&1; then
    echo "Expected incomplete seeded client sync to fail the seeded suite" >&2
    exit 1
fi
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 2 ]]
[[ "$(grep -c '^adb seeded-db-probe$' "$temp_dir/logs/events.log")" -eq 2 ]]
[[ "$(grep -c '^adb force-stop$' "$temp_dir/logs/events.log")" -eq 4 ]]
grep --quiet --fixed-strings \
    'failure_phase=login failure_category=seeded-client-sync' \
    "$client_sync_failure_output/summary.txt"

: > "$temp_dir/logs/events.log"
product_failure_output="$temp_dir/public-product-failure"
product_failure_log="$temp_dir/logs/product-failure.log"
if run_suite "$product_failure_output" env LOCKER_TEST_PRODUCT_FAIL=true > "$product_failure_log" 2>&1; then
    echo "Expected the forced product failure to fail the seeded suite" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'Seeded suite reported verified failure scenario=empty-home-and-save-options failure_phase=product failure_category=canonical-yaml' \
    "$product_failure_log"
if grep --quiet --fixed-strings 'Seeded suite failed during phase=finalize' "$product_failure_log"; then
    echo "A verified product failure was mislabeled as a finalization failure" >&2
    exit 1
fi
[[ "$(grep -c '^maestro product ' "$temp_dir/logs/events.log")" -eq 1 ]]
grep --quiet --fixed-strings \
    'seeded_suite status=fail accounts_created=1 fixture_applies=0 backend_resets=0 scenarios=1 failures=1 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=0' \
    "$product_failure_output/summary.txt"
[[ "$(grep -c '^maestro hierarchy$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(find "$product_failure_output/diagnostics" -type f -name '*-ui.txt' | wc -l | tr -d ' ')" -eq 1 ]]
grep --quiet --fixed-strings \
    'capture_status=ok route_probe=unknown collection_row_visible=false collection_title_visible=false top_right_actions=1 blue_visible=false travel_archive_row_visible=false travel_archive_title_visible=false empty_heading_visible=false empty_description_visible=false' \
    "$product_failure_output/diagnostics/empty-home-and-save-options-ui.txt"

: > "$temp_dir/logs/events.log"
collection_failure_output="$temp_dir/public-collection-failure"
if LOCKER_TEST_PRODUCT_FAIL=true \
    LOCKER_TEST_PRODUCT_FAILURE_MESSAGE='Assertion is false: "Blue Suitcase" is visible' \
    run_target_suite "$collection_failure_output" view-collection-and-item-action-menus \
    > /dev/null 2>&1; then
    echo "Expected the collection-entry assertion failure" >&2
    exit 1
fi
[[ "$(grep -c '^maestro hierarchy$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(find "$collection_failure_output/diagnostics" -type f -name '*-ui.txt' | wc -l | tr -d ' ')" -eq 1 ]]
grep --quiet --fixed-strings \
    'capture_status=ok route_probe=unknown collection_row_visible=false collection_title_visible=false top_right_actions=1 blue_visible=false travel_archive_row_visible=false travel_archive_title_visible=false empty_heading_visible=false empty_description_visible=false' \
    "$collection_failure_output/diagnostics/view-collection-and-item-action-menus-ui.txt"
if grep --recursive --quiet --extended-regexp \
    'seeded-android-proof-test@example\.org|Locker-test!Aa1' \
    "$collection_failure_output/diagnostics"; then
    echo "The product route probe leaked private hierarchy text" >&2
    exit 1
fi

: > "$temp_dir/logs/events.log"
hierarchy_failure_output="$temp_dir/public-hierarchy-failure"
if LOCKER_TEST_PRODUCT_FAIL=true \
    LOCKER_TEST_PRODUCT_FAILURE_MESSAGE='Assertion is false: "Blue Suitcase" is visible' \
    LOCKER_TEST_HIERARCHY_FAIL=true \
    run_target_suite "$hierarchy_failure_output" view-collection-and-item-action-menus \
    > /dev/null 2>&1; then
    echo "Expected the forced product failure to survive hierarchy capture failure" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'seeded_suite status=fail accounts_created=1 fixture_applies=1 backend_resets=0 scenarios=1 failures=1 identity_unchanged=true empty_login_attempts=0 seeded_login_attempts=1' \
    "$hierarchy_failure_output/summary.txt"
[[ "$(grep -c '^maestro hierarchy$' "$temp_dir/logs/events.log")" -eq 1 ]]
grep --quiet --fixed-strings \
    'capture_status=hierarchy_failed route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
    "$hierarchy_failure_output/diagnostics/view-collection-and-item-action-menus-ui.txt"

: > "$temp_dir/logs/events.log"
malformed_hierarchy_output="$temp_dir/public-malformed-hierarchy"
if LOCKER_TEST_PRODUCT_FAIL=true \
    LOCKER_TEST_PRODUCT_FAILURE_MESSAGE='Assertion is false: "Blue Suitcase" is visible' \
    LOCKER_TEST_HIERARCHY_MALFORMED=true \
    run_target_suite "$malformed_hierarchy_output" view-collection-and-item-action-menus \
    > /dev/null 2>&1; then
    echo "Expected the product failure to survive malformed hierarchy output" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'capture_status=parse_failed route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
    "$malformed_hierarchy_output/diagnostics/view-collection-and-item-action-menus-ui.txt"

: > "$temp_dir/logs/events.log"
timeout_hierarchy_output="$temp_dir/public-timeout-hierarchy"
if LOCKER_TEST_PRODUCT_FAIL=true \
    LOCKER_TEST_PRODUCT_FAILURE_MESSAGE='Assertion is false: "Blue Suitcase" is visible' \
    LOCKER_TEST_HIERARCHY_HANG=true \
    LOCKER_HIERARCHY_TIMEOUT_SECONDS=1 \
    run_target_suite "$timeout_hierarchy_output" view-collection-and-item-action-menus \
    > /dev/null 2>&1; then
    echo "Expected the product failure to survive hierarchy timeout" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'capture_status=timeout route_probe=unavailable collection_row_visible=unknown collection_title_visible=unknown top_right_actions=unknown blue_visible=unknown travel_archive_row_visible=unknown travel_archive_title_visible=unknown empty_heading_visible=unknown empty_description_visible=unknown' \
    "$timeout_hierarchy_output/diagnostics/view-collection-and-item-action-menus-ui.txt"

finish_failure_output="$temp_dir/public-finish-failure"
finish_failure_log="$temp_dir/logs/finish-failure.log"
if LOCKER_TEST_FINISH_FAIL=true \
    run_target_suite "$finish_failure_output" rename-and-delete-collections \
    > "$finish_failure_log" 2>&1; then
    echo "Expected fixture finalization failure" >&2
    exit 1
fi
grep --quiet --fixed-strings \
    'Seeded suite infrastructure failed during phase=finalize' \
    "$finish_failure_log"
if [[ -e "$finish_failure_output" ]]; then
    echo "Unverified public output survived fixture finalization failure" >&2
    exit 1
fi

rm -f "$temp_dir/logs/final-clear-ready"
clear_failure_output="$temp_dir/public-final-clear-failure"
if LOCKER_TEST_FINAL_CLEAR_FAIL=true \
    run_target_suite "$clear_failure_output" rename-and-delete-collections \
    > /dev/null 2>&1; then
    echo "Expected final app-data clear failure" >&2
    exit 1
fi
if [[ -e "$clear_failure_output" ]]; then
    echo "Unverified public output survived final app-data clear failure" >&2
    exit 1
fi

echo "Locker seeded Android runner tests passed"
