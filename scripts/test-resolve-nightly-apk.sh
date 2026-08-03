#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly resolver="$workspace_root/scripts/resolve-nightly-apk.sh"
readonly temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fixture="$temp_dir/releases.json"

printf '%s\n' '[
  {
    "draft": false,
    "tag_name": "locker-v1.0.7-beta",
    "published_at": "2026-07-31T08:00:00Z",
    "assets": [{
      "id": 201,
      "name": "ente-locker-v1.0.7-beta.apk",
      "created_at": "2026-07-31T08:00:00Z",
      "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "state": "uploaded"
    }]
  },
  {
    "draft": false,
    "tag_name": "locker-v1.0.8-rc",
    "published_at": "2026-07-30T08:00:00Z",
    "assets": [{
      "id": 202,
      "name": "ente-locker-v1.0.8-rc.apk",
      "created_at": "2026-08-01T09:00:00Z",
      "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "state": "uploaded"
    }]
  },
  {
    "draft": true,
    "tag_name": "locker-v1.0.9-beta",
    "published_at": "2026-08-02T08:00:00Z",
    "assets": [{
      "id": 203,
      "name": "ente-locker-v1.0.9-beta.apk",
      "created_at": "2026-08-02T08:00:00Z",
      "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "state": "uploaded"
    }]
  },
  {
    "draft": false,
    "tag_name": "locker-v1.0.9",
    "published_at": "2026-08-03T08:00:00Z",
    "assets": [{
      "id": 204,
      "name": "ente-locker-v1.0.9.apk",
      "created_at": "2026-08-03T08:00:00Z",
      "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "state": "uploaded"
    }]
  },
  {
    "draft": false,
    "tag_name": "auth-v4.4.25-beta",
    "published_at": "2026-08-03T08:00:00Z",
    "assets": [{
      "id": 301,
      "name": "ente-auth-v4.4.25-beta.apk",
      "created_at": "2026-08-03T09:00:00Z",
      "digest": "sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "state": "uploaded"
    }]
  }
]' > "$fixture"

expected=$'locker\trc\tlocker-v1.0.8-rc\t202\tente-locker-v1.0.8-rc.apk\t2026-08-01T09:00:00Z\tsha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\tente/nightly'
actual=$($resolver --app locker --releases-file "$fixture")
if [[ "$actual" != "$expected" ]]; then
    echo "Unexpected Locker resolution: $actual" >&2
    exit 1
fi

github_output="$temp_dir/github-output"
$resolver --app locker --releases-file "$fixture" --github-output "$github_output"
grep -Fx 'app=locker' "$github_output" > /dev/null
grep -Fx 'channel=rc' "$github_output" > /dev/null
grep -Fx 'apk_asset_id=202' "$github_output" > /dev/null
grep -Fx 'apk_created_at=2026-08-01T09:00:00Z' "$github_output" > /dev/null

jq 'map(select(.tag_name == "locker-v1.0.8-rc") | .assets[0].digest = null)' \
    "$fixture" > "$temp_dir/missing-digest.json"
if $resolver --app locker --releases-file "$temp_dir/missing-digest.json" > /dev/null 2> "$temp_dir/error"; then
    echo "Expected a missing asset digest to fail" >&2
    exit 1
fi
grep -F 'missing a valid SHA-256 asset digest' "$temp_dir/error" > /dev/null

printf '%s\n' '[]' > "$temp_dir/no-releases.json"
if $resolver --app locker --releases-file "$temp_dir/no-releases.json" > /dev/null 2> "$temp_dir/error"; then
    echo "Expected an empty release list to fail" >&2
    exit 1
fi
grep -F 'No compatible published locker APK' "$temp_dir/error" > /dev/null

if $resolver --app invalid --releases-file "$fixture" > /dev/null 2> "$temp_dir/error"; then
    echo "Expected an unknown app to fail" >&2
    exit 1
fi
grep -F -- '--app must be auth or locker' "$temp_dir/error" > /dev/null

echo "Nightly APK resolver tests passed"
