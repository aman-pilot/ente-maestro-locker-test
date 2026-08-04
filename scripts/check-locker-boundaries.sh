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
    locker/product-flows.v1.json \
    locker/provenance.v1.json \
    locker/fixtures/locker-seed.pdf \
    locker/manifests/empty.json \
    locker/stack/compose.yaml \
    .github/workflows/locker-android-seeded.yml \
    tools/locker-seed/Cargo.toml \
    tools/locker-seed/src/main.rs; do
    if git check-ignore --quiet --no-index "$public_path"; then
        echo "Expected source asset to remain visible: $public_path" >&2
        exit 1
    fi
done

if grep --recursive --line-number --binary-files=without-match --exclude=product-flows.v1.json --extended-regexp \
    'locker-maestro-worktree|mobile/mobile-tests/locker|\.\./\.\./rust/crates|server/compose\.yaml' \
    locker tools/locker-seed README.md docs; then
    echo "Legacy checkout path remains" >&2
    exit 1
fi

orchestration_paths=(scripts .github/workflows)
if grep --recursive --line-number --binary-files=without-match --ignore-case --extended-regexp \
    '(account[-_ ]?per[-_ ]?(flow|scenario|profile|shard|retry)|per[-_ ]?(flow|scenario|profile|shard|retry)[-_ ]?account|fresh[-_ ]?account[-_ ]?per[-_ ]?(flow|scenario|profile)|grouped[-_ ]?accounts?|shard[-_ ]?accounts?|account[-_ ]?pools?)' \
    "${orchestration_paths[@]}"; then
    echo "Unsupported multi-account orchestration policy is present" >&2
    exit 1
fi

if grep --recursive --line-number --binary-files=without-match --ignore-case --extended-regexp \
    '(matrix\.(account|account_context|fixture_profile|scenario)|^[[:space:]-]*(account|account_context|fixture_profile|scenario)[[:space:]]*:)' \
    .github/workflows; then
    echo "Hosted workflows must not assign accounts through a fixture-profile or scenario matrix" >&2
    exit 1
fi

while IFS= read -r script; do
    create_count="$(grep --count --extended-regexp '(^|[[:space:]])create-account([[:space:]\\]|$)' "$script" || true)"
    if (( create_count > 1 )); then
        echo "Orchestration may contain at most one account-creation call: $script" >&2
        exit 1
    fi

    if (( create_count == 1 )) && awk '
        /^[[:space:]]*(for|while|until)([[:space:]]|$)/ { loop_depth += 1 }
        /(^|[[:space:]])create-account([[:space:]\\]|$)/ && loop_depth > 0 { found = 1 }
        /^[[:space:]]*done([[:space:];]|$)/ && loop_depth > 0 { loop_depth -= 1 }
        END { exit(found ? 0 : 1) }
    ' "$script"; then
        echo "Account creation must not run inside a scenario/profile loop: $script" >&2
        exit 1
    fi
done < <(find scripts -type f -name 'run-*.sh' -print)

create_account_scripts="$(grep --files-with-matches --extended-regexp \
    '(^|[[:space:]])create-account([[:space:]\\]|$)' \
    scripts/run-*.sh 2>/dev/null || true)"
expected_create_account_scripts='scripts/run-locker-seeded-suite.sh'
if [[ "$create_account_scripts" != "$expected_create_account_scripts" ]]; then
    echo "Only audited single-account runners may orchestrate account creation" >&2
    exit 1
fi

for loopback_port in '127.0.0.1:8080:8080' '127.0.0.1:3200:3200'; do
    if ! grep --quiet --fixed-strings "$loopback_port" locker/stack/compose.yaml; then
        echo "Dedicated test ports must remain bound to loopback: $loopback_port" >&2
        exit 1
    fi
done

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
    echo "Hosted workflows must call the audited proof runner instead of assembling seeded commands directly" >&2
    exit 1
fi

if grep --quiet --extended-regexp \
    'matrix:|USER_EMAIL|USER_PASSWORD|MUSEUM_ENDPOINT|maestro test|adb ' \
    .github/workflows/locker-android-seeded.yml; then
    echo "The hosted seeded proof must remain sequential and delegate private runtime work" >&2
    exit 1
fi

if ! grep --quiet --fixed-strings \
    'scripts/run-locker-seeded-suite.sh' \
    .github/workflows/locker-android-seeded.yml; then
    echo "The hosted seeded proof must use the audited Android runner" >&2
    exit 1
fi

if grep --quiet --extended-regexp \
    '(debug|account-context|run\.json|baseline).*(path:|upload-artifact)|path:.*(debug|account-context|run\.json|baseline)' \
    .github/workflows/locker-android-seeded.yml; then
    echo "The hosted seeded proof must not upload private runtime state" >&2
    exit 1
fi

grep --quiet --fixed-strings 'local-domain-suffix: "@example.org"' locker/stack/museum.yaml
grep --quiet --fixed-strings 'local-domain-value: "123456"' locker/stack/museum.yaml
grep --quiet --fixed-strings 'ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_SUFFIX: "@example.org"' locker/stack/compose.yaml
grep --quiet --fixed-strings 'ENTE_INTERNAL_HARDCODED_OTT_LOCAL_DOMAIN_VALUE: "123456"' locker/stack/compose.yaml

echo "Locker source/private boundaries passed"
