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
| Account lifecycle decision | Catalog and runtime policy require one online account, one shared fixture application, and no intra-lane backend reset. |
| Seeder runtime | The active online fixture has encrypted apply/read-back support; inactive manifests remain reference inputs for later promotion. |
| Hosted account-free Android | API 34 x86_64 passed onboarding against published asset `500679355` with its exact SHA-256. |
| Product YAML ownership | This repository canonically owns all 31 flows, their source snapshot hashes, and their core/platform/paid classifications. |
| Profile/reset orchestration | Scenario-to-profile mappings, baseline capture/restore code, and the reset-only hosted proof were removed. |
| Seeded Android orchestration | Static and mocked tests prove one account, one fixture apply, zero backend resets, two cold-login boundaries, private login arguments, and credential-free product invocation. |
| Hosted private login | Rootable API 34 x86_64 pre-seeds `flutter.endpoint`; bounded retries reuse the same identity and never create another account. |
| Exact-APK product entry | The manual workflow resolves and verifies the exact published APK, produces leakage-scanned JUnit, and has reached canonical product YAML for all four initial scenarios. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Seeded info visibility | `search-note-secret-and-thing` remains on the empty home after a verified Museum apply/read-back, so the published APK never exposes `Search your documents`. Diagnose app collection/file sync against the exact asset or publish a compatible Locker build; do not weaken the fixture assertion. |
| Settings-search semantics | `locker-v1.0.8-beta` predates the `Search settings` tooltip present in newer source. Publish an APK with that accessibility contract, then rerun the canonical selector. |
| Exact-APK seeded gate | Rerun the manual four-flow workflow after the two published-app blockers above are available in one exact asset. |
| Product/nightly compatibility | Remaining collection, Trash, selector, and rename/move candidates must be promoted incrementally only after the four-flow core gate passes. |
| Native platform flows | Keep picker, viewer, download, and offline/network behavior outside the first hosted seeded gate. |

## Current evidence boundary

The account-free onboarding flow passed locally using Locker asset `499393890`
and Maestro 2.6.1 on an API 35 ARM emulator. The 25/26 counts retained under
catalog `historicalEvidence` came from the source prototype and do not prove
this repository, current manifests, current APK, hosted execution, or the
single-account-per-run contract. That evidence is historical and noncanonical.

Product YAML is present. Run `30888541387` used the retired reset-per-profile
runner and is historical evidence only. It produced four product JUnit files:
empty-home and account/security passed, while seeded search visibility and
settings-search semantics failed. The new online-only one-fixture lane has not
yet been hosted-proven and remains red until all four flows pass.
