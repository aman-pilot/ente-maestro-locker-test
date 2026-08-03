#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/download-locker-nightly.sh [--output-dir <path>]

Downloads the newest compatible Locker APK from ente/nightly and verifies it
against the release asset's SHA-256 digest. Prints the verified APK path.
EOF
}

output_dir="artifacts/locker"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir)
            output_dir="${2:?--output-dir requires a path}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

IFS=$'\t' read -r app channel release_tag apk_asset_id apk_name apk_created_at apk_sha256 source_repository < <(
    "$(dirname "${BASH_SOURCE[0]}")/resolve-nightly-apk.sh" --app locker
)

mkdir -p "$output_dir"
apk_path="$output_dir/$apk_name"
partial_path=$(mktemp "$output_dir/.${apk_name}.XXXXXX")
cleanup() {
    rm -f "$partial_path"
}
trap cleanup EXIT
gh api \
    -H 'Accept: application/octet-stream' \
    "repos/$source_repository/releases/assets/$apk_asset_id" > "$partial_path"

expected_sha256="${apk_sha256#sha256:}"
if command -v sha256sum > /dev/null; then
    actual_sha256=$(sha256sum "$partial_path" | awk '{print $1}')
elif command -v shasum > /dev/null; then
    actual_sha256=$(shasum -a 256 "$partial_path" | awk '{print $1}')
else
    echo "Neither sha256sum nor shasum is available" >&2
    exit 2
fi

if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    echo "Downloaded Locker APK does not match the resolved release asset" >&2
    exit 1
fi

mv "$partial_path" "$apk_path"
trap - EXIT
echo "Verified $release_tag asset $apk_asset_id created $apk_created_at ($expected_sha256)" >&2
printf '%s\n' "$apk_path"
