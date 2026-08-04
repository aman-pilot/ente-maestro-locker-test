# Locker repository blocker status

Snapshot: 2026-08-04

## Cleared

| Blocker | Current handling |
| --- | --- |
| Empty standalone repository | Locker-owned layout, scripts, docs, workflows, smoke, fixtures, catalog, seeder, and stack are present. |
| Published APK discovery and reused tags | Resolution records exact asset ID, creation time, filename, source, and SHA-256. |
| Source-checkout Rust dependencies | `ente-accounts` and `ente-core` use the same full Ente Git revision. |
| Source-built backend | Compose uses only digest-pinned Museum, PostgreSQL, MinIO, MinIO client, and socat images. |
| Implicit MinIO bucket mutation | A one-shot `minio-init` service creates all required buckets. |
| Standalone stack on local Docker | PostgreSQL became healthy, all buckets were created, Museum returned `pong`, and socat started; the dedicated stack and volumes were then removed. |
| Legacy checkout paths | Static boundaries reject Ente source-tree and old test-worktree references. |
| Fixture drift | Catalog structure, manifest references, public files, hashes, and Compose provenance are statically checked. |
| Private state leakage | Account contexts, run records, evidence, Cargo targets, and downloaded artifacts are ignored and rejected from active workflow wiring. |
| Account lifecycle decision | Catalog and runtime policy require exactly one synthetic account per isolated run, reused across all profiles with no fallback account. |
| Reset mechanism | PostgreSQL template restore plus MinIO object/version/incomplete-upload clearing preserves the account while removing fixture rows, diffs, sequences, and objects. |
| Single-account runtime proof | One account sequentially passed structured-item, document/thumbnail, multi-membership, and Trash manifests with three verified resets. |
| Seeder runtime | Four representative manifests passed encrypted apply, download/decrypt verification, and inspection against the local pinned stack. |
| Hosted x86 stack and reset | The pinned stack and four-profile one-account proof passed on hosted Ubuntu x86 with three verified resets. |
| Hosted account-free Android | API 34 x86_64 passed onboarding against published asset `500679355` with its exact SHA-256. |
| Product YAML ownership | This repository canonically owns all 31 flows, their source snapshot hashes, and their core/platform/paid classifications. |
| Fresh-account-per-flow text | Imported comments now describe the same-account reset fixture instead of the discarded multiple-account lifecycle. |
| Seeded Android orchestration | Static and mocked tests prove app-data clearing, reverse-port checks, mode-0600 private login arguments, separate credential-free product invocation, one account, and three resets. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Exact-APK seeded proof | Run the manual four-flow seeded workflow on hosted API 34 x86_64 and classify any published-nightly compatibility failure. |
| Product/nightly compatibility | Required collection, Trash, selector, and rename/move behavior must reach a published APK. |
| Native platform flows | Keep picker, viewer, download, and offline/network behavior outside the first hosted seeded gate. |

## Current evidence boundary

The account-free onboarding flow passed locally using Locker asset `499393890`
and Maestro 2.6.1 on an API 35 ARM emulator. The 25/26 counts retained under
catalog `historicalEvidence` came from the source prototype and do not prove
this repository, current manifests, current APK, hosted execution, or the
single-account-per-run contract. That evidence is historical and noncanonical.

Product YAML is present but has not been promoted to product-flow coverage. No
login prelude, account credentials, run record, seeded Android workflow, or
seeded-result artifact has been imported. The local single-account proof is
seeder evidence, not product-flow coverage.
