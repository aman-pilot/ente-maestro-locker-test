#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly selector="$workspace_root/scripts/select-locker-ci-suites.sh"

reachable=""
queue=()

contains_line() {
    local lines=$1
    local candidate=$2
    [[ $'\n'"$lines"$'\n' == *$'\n'"$candidate"$'\n'* ]]
}

enqueue() {
    local flow=$1
    if ! contains_line "$reachable" "$flow"; then
        reachable+="${reachable:+$'\n'}$flow"
        queue+=("$flow")
    fi
}

collect_reachable() {
    local dependency dependency_absolute dependency_path flow source_path

    while [[ ${#queue[@]} -gt 0 ]]; do
        flow=${queue[0]}
        queue=("${queue[@]:1}")
        if [[ ! -f "$workspace_root/$flow" ]]; then
            echo "Registered Maestro flow does not exist: $flow" >&2
            exit 1
        fi

        while IFS= read -r dependency; do
            source_path="$(dirname "$workspace_root/$flow")/$dependency"
            if [[ ! -f "$source_path" ]]; then
                echo "Registered Maestro dependency does not exist: $flow -> $dependency" >&2
                exit 1
            fi
            dependency_absolute=$(realpath "$source_path")
            dependency_path=${dependency_absolute#"$workspace_root/"}
            case "$dependency_path" in
                maestro/locker/onboarding/*)
                    enqueue "$dependency_path"
                    ;;
                *)
                    echo "Maestro flow escapes its hosted scope: $flow -> $dependency_path" >&2
                    exit 1
                    ;;
            esac
        done < <(sed -En "s/^[[:space:]]*file:[[:space:]]*['\"]?([^'\"]+)['\"]?[[:space:]]*$/\1/p" "$workspace_root/$flow")
    done
}

matrix=$($selector --all)
while IFS= read -r flow; do
    [[ -n "$flow" ]] && enqueue "$flow"
done < <(jq -r '.include[].flows' <<< "$matrix" | tr ' ' '\n')
collect_reachable

while IFS= read -r flow; do
    if ! contains_line "$reachable" "$flow"; then
        echo "Hosted Locker Maestro flow is not registered in a suite: $flow" >&2
        exit 1
    fi
done < <(find "$workspace_root/maestro/locker/onboarding" -name '*.yaml' -type f | sed "s|^$workspace_root/||" | sort)

echo "Hosted Locker Maestro flow registration tests passed"
