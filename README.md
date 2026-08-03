# Ente Locker Maestro tests

Standalone test infrastructure for published Ente Locker Android builds. The
repository is being proven separately before its Locker-owned paths are merged
beside Auth coverage in `aman-pilot/ente-maestro-tests`.

## Current scope

Two independent layers are present:

- a published-build, account-free onboarding smoke flow;
- lifecycle-neutral seeded-test infrastructure: 22 manifests, 20 fixture
  profiles, 31 scenario records, binary fixtures, a Rust E2EE seeder, and a
  digest-pinned Museum/PostgreSQL/MinIO stack.

The 31 product Maestro YAML flows are intentionally not imported. No hosted
workflow creates accounts, starts the seeded stack, or runs the seeder. The
catalog records the starting inventory each future scenario needs but does not
choose whether accounts are created, restored, reset, pooled, reused, or split
across scenario groups.

## Repository layout

| Path | Owns |
| --- | --- |
| `locker/catalog.v1.json` | YAML-free fixture profiles and scenario-to-fixture knowledge. |
| `locker/provenance.v1.json` | Ente revision, image digests, and fixture hashes. |
| `locker/manifests/` | Encrypted starting-state descriptions for Locker. |
| `locker/fixtures/` | Public synthetic files used by document fixtures. |
| `locker/stack/` | Self-contained digest-pinned local backend stack. |
| `tools/locker-seed/` | Rust manifest validation, explicit account-context creation, E2EE seeding, and read-back verification. |
| `maestro/locker/smoke/` | Public, account-free published-build smoke flows. |
| `scripts/` | Static contracts, nightly resolution, download, selection, and local Android execution. |
| `.github/workflows/` | Static validation and manual published-nightly Android smoke. |

The Locker-owned paths avoid Auth's top-level `museum/` and fixture-generator
paths so the repositories can be merged without renaming either implementation.

## Validate locally

The complete static gate validates shell and YAML syntax, workflow security,
fixture/catalog integrity, provenance hashes, Cargo dependencies and tests, and
the rendered Compose model. It does not start Docker, create an account, run
Maestro, or require credentials.

```sh
scripts/check-static.sh
```

Resolve the current published Locker build without downloading it:

```sh
scripts/resolve-nightly-apk.sh --app locker
```

Run the account-free onboarding suite on one connected Android device:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-android-local.sh --apk "$apk_path" --suite onboarding
```

## Seeded infrastructure boundary

The seeder takes a private account context for `apply`; it does not decide how
that context is assigned to scenarios. `create-account` is an explicit low-level
local capability, not a suite policy and not a hosted workflow step.

```sh
cargo run --manifest-path tools/locker-seed/Cargo.toml -- \
  validate --manifest locker/manifests/search-note-secret-and-thing.json
```

Private account contexts and run records must stay outside source control. The
repository ignores `locker/runs/`, and future orchestration should prefer the
runner's temporary directory.

See [docs/seeded-runtime-decisions.md](docs/seeded-runtime-decisions.md) for the
account-lifecycle choice deliberately left until after the infrastructure is
proven.

## Verification status

The account-free onboarding flow passed locally against
`locker-v1.0.8-beta`, asset `499393890`, SHA-256
`65df6d18b9ee7837c28b0b13ac75c863fa47a44efcf3d64bb6f306d2a8c8cc3f`,
on an API 35 ARM emulator with Maestro 2.6.1. This is local evidence, not a
hosted-coverage claim. The digest-pinned backend stack also passed a local
runtime check: PostgreSQL became healthy, MinIO created all required buckets,
Museum returned `pong`, and socat started; its dedicated containers and volumes
were then removed. No account was created. The imported seeded evidence in the
catalog is historical context only; this standalone repository has not run the
seeded product suite.
