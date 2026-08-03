#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/select-locker-ci-suites.sh --all
  scripts/select-locker-ci-suites.sh --suite <onboarding>
  scripts/select-locker-ci-suites.sh --changed-file <path> [--changed-file <path> ...]
  scripts/select-locker-ci-suites.sh <base-revision> <head-revision>

Print the hosted Locker Android CI matrix for the supplied changes.
EOF
}

if ! command -v jq > /dev/null; then
    echo "Required command is not available: jq" >&2
    exit 2
fi

full_matrix=false
requested_suite=""
changed_files=()

case "${1:-}" in
    --all)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        full_matrix=true
        ;;
    --suite)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        requested_suite=$2
        ;;
    --changed-file)
        while [[ $# -gt 0 ]]; do
            [[ "$1" == "--changed-file" && $# -ge 2 ]] || {
                usage >&2
                exit 2
            }
            changed_files+=("$2")
            shift 2
        done
        ;;
    *)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        while IFS= read -r changed_file; do
            [[ -n "$changed_file" ]] && changed_files+=("$changed_file")
        done < <(git diff --name-only "$1" "$2")
        ;;
esac

readonly suite_order=(onboarding)
selected_suites=""

add_suite() {
    local suite=$1
    if [[ ",$selected_suites," != *",$suite,"* ]]; then
        selected_suites+="${selected_suites:+,}$suite"
    fi
}

if [[ -n "$requested_suite" ]]; then
    case "$requested_suite" in
        onboarding) add_suite "$requested_suite" ;;
        *) echo "Unknown hosted Locker suite: $requested_suite" >&2; exit 2 ;;
    esac
fi

if [[ ${#changed_files[@]} -gt 0 ]]; then
    for changed_file in "${changed_files[@]}"; do
        case "$changed_file" in
            .github/workflows/locker-android-smoke.yml|.github/workflows/locker-static.yml|scripts/check-static.sh|scripts/check-workflow-security.rb|scripts/download-locker-nightly.sh|scripts/resolve-nightly-apk.sh|scripts/run-locker-android-local.sh|scripts/select-locker-ci-suites.sh|scripts/test-download-locker-nightly.sh|scripts/test-hosted-flow-registration.sh|scripts/test-resolve-nightly-apk.sh|scripts/test-run-locker-android-local.sh|scripts/test-select-locker-ci-suites.sh|maestro/locker/subflows/*)
                full_matrix=true
                ;;
            maestro/locker/smoke/onboarding.yaml)
                add_suite onboarding
                ;;
            maestro/locker/smoke/*.yaml)
                # A new hosted flow must not silently receive no coverage.
                full_matrix=true
                ;;
            maestro/locker/platform/*|docs/*|README.md)
                ;;
        esac
    done
fi

if [[ "$full_matrix" == true ]]; then
    selected_suites="$(IFS=,; echo "${suite_order[*]}")"
fi

matrix='{"include":[]}'
for suite in "${suite_order[@]}"; do
    [[ ",$selected_suites," == *",$suite,"* ]] || continue
    case "$suite" in
        onboarding)
            name="Published Locker onboarding"
            flows="maestro/locker/smoke/onboarding.yaml"
            coverage="fresh application launch and public onboarding actions"
            ;;
    esac
    matrix=$(jq -c \
        --arg name "$name" \
        --arg suite "$suite" \
        --arg flows "$flows" \
        --arg coverage "$coverage" \
        '.include += [{name: $name, suite: $suite, flows: $flows, coverage: $coverage}]' \
        <<< "$matrix")
done

printf '%s\n' "$matrix"
