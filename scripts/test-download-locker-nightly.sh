#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly downloader="$workspace_root/scripts/download-locker-nightly.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

mkdir -p "$temp_dir/bin"
payload='published-locker-apk-fixture'
if command -v sha256sum > /dev/null; then
    digest=$(printf '%s' "$payload" | sha256sum | awk '{print $1}')
else
    digest=$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')
fi

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ $* == *"releases/assets/9001"* ]]; then' \
    '    if [[ ${LOCKER_TEST_BAD_ASSET:-0} == 1 ]]; then printf bad; else printf "%s" "$LOCKER_TEST_PAYLOAD"; fi' \
    '    exit 0' \
    'fi' \
    'printf "[{\"draft\":false,\"tag_name\":\"locker-v1.2.3-beta\",\"assets\":[{\"id\":9001,\"name\":\"ente-locker-v1.2.3-beta.apk\",\"created_at\":\"2026-08-03T00:00:00Z\",\"digest\":\"sha256:%s\",\"state\":\"uploaded\"}]}]\\n" "$LOCKER_TEST_DIGEST"' \
    > "$temp_dir/bin/gh"
chmod +x "$temp_dir/bin/gh"

downloaded=$(
    cd "$temp_dir"
    PATH="$temp_dir/bin:$PATH" \
    LOCKER_TEST_DIGEST="$digest" \
    LOCKER_TEST_PAYLOAD="$payload" \
        "$downloader" --output-dir "$temp_dir/downloads"
)

[[ "$downloaded" == "$temp_dir/downloads/ente-locker-v1.2.3-beta.apk" ]]
[[ "$(< "$downloaded")" == "$payload" ]]

if (
    cd "$temp_dir"
    PATH="$temp_dir/bin:$PATH" \
    LOCKER_TEST_BAD_ASSET=1 \
    LOCKER_TEST_DIGEST="$digest" \
    LOCKER_TEST_PAYLOAD="$payload" \
        "$downloader" --output-dir "$temp_dir/bad-download" > /dev/null 2>&1
); then
    echo "Expected a mismatched Locker APK digest to fail" >&2
    exit 1
fi

if find "$temp_dir/bad-download" -type f -print -quit | grep -q .; then
    echo "A failed Locker APK download left a partial file" >&2
    exit 1
fi

echo "Locker nightly download tests passed"
