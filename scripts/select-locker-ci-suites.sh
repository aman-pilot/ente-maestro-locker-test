#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/select-locker-ci-suites.sh --all
  scripts/select-locker-ci-suites.sh --suite onboarding

Print the hosted Locker Android smoke matrix.
EOF
}

case "${1:-}" in
    --all)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        ;;
    --suite)
        [[ $# -eq 2 ]] || { usage >&2; exit 2; }
        if [[ "$2" != onboarding ]]; then
            echo "Unknown hosted Locker suite: $2" >&2
            exit 2
        fi
        ;;
    -h|--help)
        [[ $# -eq 1 ]] || { usage >&2; exit 2; }
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

cat <<'JSON'
{"include":[{"name":"Published Locker onboarding","suite":"onboarding","flows":"maestro/locker/smoke/onboarding.yaml","coverage":"fresh application launch and public onboarding actions"}]}
JSON
