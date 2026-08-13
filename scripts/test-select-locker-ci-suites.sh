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

assert_suites onboarding --all
assert_suites onboarding --suite onboarding
assert_flows onboarding "maestro/locker/onboarding/onboarding.yaml" --all

if "$selector" --suite unknown > /dev/null 2>&1; then
    echo "Expected an unknown suite to fail" >&2
    exit 1
fi

if "$selector" --unknown > /dev/null 2>&1; then
    echo "Expected an unknown selection mode to fail" >&2
    exit 1
fi

if "$selector" > /dev/null 2>&1; then
    echo "Expected a missing selection mode to fail" >&2
    exit 1
fi

echo "Locker CI suite selection tests passed"
