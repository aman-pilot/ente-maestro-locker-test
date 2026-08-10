#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runner="$workspace_root/scripts/run-locker-android-local.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin" "$temp_dir/logs"
touch "$temp_dir/locker.apk"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == --version ]]; then echo 2.6.1; exit 0; fi' \
    'printf "%s\n" "$*" >> "$LOCKER_TEST_LOG/maestro.log"' \
    > "$temp_dir/bin/maestro"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" >> "$LOCKER_TEST_LOG/adb.log"' \
    'if [[ $* == *"get-state"* ]]; then echo device; fi' \
    > "$temp_dir/bin/adb"

chmod +x "$temp_dir/bin/maestro" "$temp_dir/bin/adb"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo 2.5.1' \
    > "$temp_dir/bin/wrong-maestro"
chmod +x "$temp_dir/bin/wrong-maestro"

if PATH="$temp_dir/bin:$PATH" \
    LOCKER_TEST_LOG="$temp_dir/logs" \
    "$runner" \
        --apk "$temp_dir/locker.apk" \
        --maestro "$temp_dir/bin/wrong-maestro" \
        --serial emulator-test \
        --suite onboarding > /dev/null 2>&1; then
    echo "Expected a mismatched Maestro version to fail" >&2
    exit 1
fi

PATH="$temp_dir/bin:$PATH" \
LOCKER_TEST_LOG="$temp_dir/logs" \
LOCKER_MAESTRO_OUTPUT_DIR="$temp_dir/output" \
    "$runner" \
        --apk "$temp_dir/locker.apk" \
        --maestro "$temp_dir/bin/maestro" \
        --serial emulator-test \
        --suite onboarding

grep -F -- '-s emulator-test install -r' "$temp_dir/logs/adb.log" > /dev/null
grep -F -- '-e APP_ID=io.ente.locker.independent' "$temp_dir/logs/maestro.log" > /dev/null
grep -F -- 'maestro/locker/smoke/onboarding.yaml' "$temp_dir/logs/maestro.log" > /dev/null
grep -F -- "$temp_dir/output/onboarding-results.xml" "$temp_dir/logs/maestro.log" > /dev/null

if PATH="$temp_dir/bin:$PATH" \
    LOCKER_TEST_LOG="$temp_dir/logs" \
    "$runner" --apk "$temp_dir/missing.apk" --maestro "$temp_dir/bin/maestro" --serial emulator-test > /dev/null 2>&1; then
    echo "Expected a missing APK to fail" >&2
    exit 1
fi

if PATH="$temp_dir/bin:$PATH" \
    LOCKER_TEST_LOG="$temp_dir/logs" \
    "$runner" --apk "$temp_dir/locker.apk" --maestro "$temp_dir/bin/maestro" --serial emulator-test --suite unknown > /dev/null 2>&1; then
    echo "Expected an unknown suite to fail" >&2
    exit 1
fi

echo "Locker local Android runner tests passed"
