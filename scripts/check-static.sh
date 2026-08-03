#!/usr/bin/env bash

set -euo pipefail

readonly workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$workspace_root"

for command in bash cargo docker git jq ruby; do
    if ! command -v "$command" > /dev/null; then
        echo "Required command is not available: $command" >&2
        exit 2
    fi
done

scripts/test-select-locker-ci-suites.sh
scripts/test-hosted-flow-registration.sh
scripts/test-resolve-nightly-apk.sh
scripts/test-download-locker-nightly.sh
scripts/test-run-locker-android-local.sh
scripts/check-locker-boundaries.sh
ruby scripts/check-locker-assets.rb

cargo fmt --manifest-path tools/locker-seed/Cargo.toml --check
cargo test --manifest-path tools/locker-seed/Cargo.toml --locked
cargo check --manifest-path tools/locker-seed/Cargo.toml --locked

docker compose --file locker/stack/compose.yaml config --quiet
echo "Standalone Locker stack configuration passed"

while IFS= read -r script; do
    bash -n "$script"
done < <(find scripts -type f -name '*.sh' | sort)
echo "Shell syntax checks passed"

ruby -e '
  require "psych"
  files = Dir.glob("maestro/locker/**/*.yaml").sort
  abort("No Locker Maestro YAML files found") if files.empty?
  files.each { |file| Psych.parse_stream(File.read(file), filename: file) }
  puts "YAML syntax checks passed: #{files.length} files"
'

ruby scripts/check-workflow-security.rb
git diff --check

echo "Locker Maestro static checks passed"
