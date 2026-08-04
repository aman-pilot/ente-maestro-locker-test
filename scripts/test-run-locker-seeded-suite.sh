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
    '  *"shell am get-current-user"*) echo 0 ;;' \
    '  *"shell stat -c"*) echo 10000:10000 ;;' \
    '  *"shell pm clear"*) echo Success; echo "adb pm-clear" >> "$LOCKER_EVENT_LOG" ;;' \
    '  *"reverse --list"*) printf "emulator-test tcp:8080 tcp:8080\nemulator-test tcp:3200 tcp:3200\n" ;;' \
    '  *"reverse tcp:"*) echo "adb reverse" >> "$LOCKER_EVENT_LOG" ;;' \
    'esac' \
    > "$temp_dir/bin/adb"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then echo 2.6.1; exit 0; fi' \
    'printf "maestro %s\n" "$*" >> "$LOCKER_TEST_LOG/maestro.log"' \
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
    '    printf "%s\n" "{\"endpoint\":\"http://127.0.0.1:8080\",\"email\":\"seeded-android-proof-test@example.org\",\"password\":\"Locker-test!Aa1\",\"userId\":42}" > "$run_dir/run.json"' \
    '    chmod 600 "$run_dir/run.json"' \
    '    echo "seeder apply $scenario" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    '  inspect)' \
    '    echo "{}"' \
    '    ;;' \
    '  finish)' \
    '    run_dir=""; previous=""' \
    '    for argument in "$@"; do [[ "$previous" == --run-dir ]] && run_dir="$argument"; previous="$argument"; done' \
    '    rm -f "$run_dir/run.json"' \
    '    echo "{}"' \
    '    echo "seeder finish $(basename "$run_dir")" >> "$LOCKER_EVENT_LOG"' \
    '    ;;' \
    'esac' \
    > "$temp_dir/bin/locker-seed"

chmod +x "$temp_dir/bin/adb" "$temp_dir/bin/docker" "$temp_dir/bin/locker-seed" "$temp_dir/bin/maestro"

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

output_dir="$temp_dir/public-pass"
run_suite "$output_dir" env

[[ "$(grep -c 'seeder create-account' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder reset$' "$temp_dir/logs/events.log" || true)" -eq 0 ]]
[[ "$(grep -c '^seeder apply online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^seeder finish online-fixture$' "$temp_dir/logs/events.log")" -eq 1 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 2 ]]
[[ "$(grep -c '^maestro product ' "$temp_dir/logs/events.log")" -eq 4 ]]
[[ "$(grep -c '^adb reverse$' "$temp_dir/logs/events.log")" -eq 4 ]]
[[ "$(grep -c '^adb pm-clear$' "$temp_dir/logs/events.log")" -ge 4 ]]
[[ "$(grep -c 'flutter.endpoint' "$temp_dir/logs/adb.log")" -ge 2 ]]

grep --quiet --fixed-strings \
    'seeded_suite status=pass accounts_created=1 fixture_applies=1 backend_resets=0 scenarios=4 failures=0 identity_unchanged=true' \
    "$output_dir/summary.txt"
[[ "$(find "$output_dir/results" -type f -name '*.xml' | wc -l | tr -d ' ')" -eq 4 ]]
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
[[ "$(grep -c 'failure_phase=login failure_category=initial-login-screen' "$login_failure_output/summary.txt")" -eq 4 ]]
[[ "$(grep -c '^maestro login$' "$temp_dir/logs/events.log")" -eq 2 ]]
if [[ -d "$login_failure_output/results" ]] && find "$login_failure_output/results" -type f | grep --quiet .; then
    echo "Product JUnit exists even though private login failed" >&2
    exit 1
fi

echo "Locker seeded Android runner tests passed"
