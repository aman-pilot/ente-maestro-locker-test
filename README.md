# Ente Locker Maestro tests

Standalone test infrastructure for published Ente Locker Android builds. The
repository is being proven separately before its Locker-owned paths are merged
beside Auth coverage in `aman-pilot/ente-maestro-tests`.

## Current scope

Two independent layers are present:

- a published-build, account-free onboarding smoke flow;
- single-account seeded-test infrastructure: 22 manifests, 20 fixture
  profiles, 31 scenario records, binary fixtures, a Rust E2EE seeder, and a
  digest-pinned Museum/PostgreSQL/MinIO stack.

The 31 product Maestro YAML flows are intentionally not imported. No hosted
workflow creates accounts, starts the seeded stack, or runs the seeder. The
catalog records the starting inventory each future scenario needs but does not
yet make those product scenarios runnable. The runtime contract is already
fixed: one isolated run creates exactly one temporary synthetic account and
reuses that same identity for every profile, resetting it to the required
baseline before each scenario. A flow, fixture profile, shard, or retry must
never create an additional account.

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

The seeder takes a private account context for `apply`. Runtime orchestration
may call the low-level `create-account` command exactly once at the start of an
isolated run. It then captures an empty PostgreSQL account template and every
later profile uses the same email, user ID, and private context after a
fail-closed backend restore. The reset proof is local only; no hosted seeded
runtime is enabled yet.

```sh
cargo run --manifest-path tools/locker-seed/Cargo.toml -- \
  validate --manifest locker/manifests/search-note-secret-and-thing.json
```

Private account contexts and run records must stay outside source control. The
repository ignores `locker/runs/`, and future orchestration should prefer the
runner's temporary directory.

See [docs/seeded-runtime-decisions.md](docs/seeded-runtime-decisions.md) for the
fixed identity lifecycle and selected reset mechanism. The complete local
proof and timings are recorded in
[docs/single-account-proof.md](docs/single-account-proof.md).

Run the same-account fixture proof locally with Docker Desktop running:

```sh
scripts/run-locker-single-account-proof.sh
```

The script owns a unique Compose project, creates one account, applies four
representative manifests sequentially, resets between them, and removes its
private directory and Docker volumes through an exit trap. The dedicated
Museum and MinIO ports bind to `127.0.0.1` only.

## Verification status

The account-free onboarding flow passed locally against
`locker-v1.0.8-beta`, asset `499393890`, SHA-256
`65df6d18b9ee7837c28b0b13ac75c863fa47a44efcf3d64bb6f306d2a8c8cc3f`,
on an API 35 ARM emulator with Maestro 2.6.1. This is local evidence, not a
hosted-coverage claim. The digest-pinned backend stack also passed a local
runtime check: PostgreSQL became healthy, MinIO created all required buckets,
Museum returned `pong`, and socat started; its dedicated containers and volumes
were then removed. No account was created during that backend-only check. The
standalone seeder has since passed a four-profile single-account proof for
structured items, documents and thumbnails, multiple memberships, and Trash.
This proves fixture reset/reuse only; it does not prove product Maestro flows.

Historical prototype results retained in the catalog are explicitly
noncanonical: the prototype's account behavior and pass counts do not satisfy
or prove this repository's single-account runtime.
