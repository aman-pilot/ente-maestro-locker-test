#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workspace_root"

for private_path in \
    artifacts/example.txt \
    locker/evidence/example.json \
    locker/runs/example/run.json \
    tools/locker-seed/target/debug/locker-seed; do
    if ! git check-ignore --quiet --no-index "$private_path"; then
        echo "Expected generated/private path to be ignored: $private_path" >&2
        exit 1
    fi
done

for public_path in \
    locker/catalog.v1.json \
    locker/provenance.v1.json \
    locker/fixtures/locker-seed.pdf \
    locker/manifests/empty.json \
    locker/stack/compose.yaml \
    tools/locker-seed/Cargo.toml \
    tools/locker-seed/src/main.rs; do
    if git check-ignore --quiet --no-index "$public_path"; then
        echo "Expected source asset to remain visible: $public_path" >&2
        exit 1
    fi
done

if grep --recursive --line-number --binary-files=without-match --extended-regexp \
    'fresh-account-per-flow|locker-maestro-worktree|mobile/mobile-tests/locker|\.\./\.\./rust/crates|server/compose\.yaml' \
    locker tools/locker-seed README.md docs; then
    echo "Legacy checkout path or decided account policy remains" >&2
    exit 1
fi

if find . \
    -path './.git' -prune -o \
    -path './artifacts' -prune -o \
    -path './tools/locker-seed/target' -prune -o \
    -type f \( -name run.json -o -name account-context.json -o -name credentials.json \) \
    -print | grep -q .; then
    echo "A private account or run record is present in the source tree" >&2
    exit 1
fi

while IFS= read -r json_file; do
    if jq --exit-status \
        'type == "object" and has("endpoint") and has("email") and has("password")' \
        "$json_file" > /dev/null 2>&1; then
        echo "A source-visible JSON file looks like a private account context: $json_file" >&2
        exit 1
    fi
done < <(find . \
    -path './.git' -prune -o \
    -path './artifacts' -prune -o \
    -path './tools/locker-seed/target' -prune -o \
    -type f -name '*.json' -print)

if grep --recursive --quiet --extended-regexp \
    'locker-seed (create-account|apply)|locker/stack/compose\.yaml' \
    .github/workflows; then
    echo "Seeded runtime must stay disabled in hosted workflows until lifecycle and YAML decisions are made" >&2
    exit 1
fi

grep --quiet --fixed-strings 'local-domain-suffix: "@example.org"' locker/stack/museum.yaml
grep --quiet --fixed-strings 'local-domain-value: "123456"' locker/stack/museum.yaml
grep --quiet --fixed-strings 'ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_SUFFIX: "@example.org"' locker/stack/compose.yaml
grep --quiet --fixed-strings 'ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_VALUE: "123456"' locker/stack/compose.yaml

echo "Locker source/private boundaries passed"
