#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-locker-ci-suites.sh"

assert_suites() {
    local expected=$1
    shift
    local actual
    actual=$("$selector" "$@" | jq -r '.include | map(.suite) | join(",")')
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected suites '$expected', got '$actual' for: $*" >&2
        exit 1
    fi
}

assert_flows() {
    local suite=$1
    local expected=$2
    shift 2
    local actual
    actual=$("$selector" "$@" | jq -r --arg suite "$suite" '.include[] | select(.suite == $suite) | .flows')
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected flows '$expected', got '$actual' for suite '$suite'" >&2
        exit 1
    fi
}

assert_suites onboarding --changed-file maestro/locker/smoke/onboarding.yaml
assert_suites onboarding --changed-file maestro/locker/smoke/new-hosted-flow.yaml
assert_suites "" --changed-file maestro/locker/online/subflows/new-online-helper.yaml
assert_suites onboarding --changed-file scripts/resolve-nightly-apk.sh
assert_suites onboarding --changed-file scripts/test-hosted-flow-registration.sh
assert_suites onboarding --all
assert_suites onboarding --suite onboarding
assert_suites "" --changed-file maestro/locker/online/platform/native-picker.yaml
assert_suites "" --changed-file README.md
assert_suites "" --changed-file docs/locker-test-rollout.md
assert_flows onboarding "maestro/locker/smoke/onboarding.yaml" --all

if "$selector" --suite unknown > /dev/null 2>&1; then
    echo "Expected an unknown suite to fail" >&2
    exit 1
fi

echo "Locker CI suite selection tests passed"
