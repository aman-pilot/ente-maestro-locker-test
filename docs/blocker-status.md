# Locker repository blocker status

Snapshot: 2026-08-06

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
| Product YAML ownership | This repository canonically owns all 31 flows, their source snapshot hashes, and their online/platform/paid classifications. |
| Profile/reset orchestration | Scenario-to-profile mappings, baseline capture/restore code, and the reset-only hosted proof were removed. |
| Seeded Android orchestration | Static and mocked tests prove one account, one fixture apply, zero backend resets, two cold-login boundaries, private login arguments, credential-free product invocation, and public per-boundary login-attempt counts. |
| Hosted private login | Rootable API 34 x86_64 pre-seeds `flutter.endpoint`; bounded retries reuse the same identity and never create another account. |
| Exact-APK product entry | The manual workflow resolves and verifies the exact published APK, produces leakage-scanned JUnit, and has reached canonical product YAML for all four initial scenarios. |
| Source-built seeded visibility | The four-flow online lane passed locally on API 35 ARM with source-built independent APK SHA-256 `e71d456c9a571d293269c1c076912f7a8a124560f4d20a73803e5824e99b66f3`; seeded Note, Secret, and Thing search is visible after cold login, and both empty and seeded logins completed on attempt one. |
| Source-built settings semantics | The same four-flow proof passed `Open navigation menu` and `Search settings` against the current Locker source build. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Exact published seeded gate | Publish one Locker APK containing the proven collection-sync and semantics changes, then rerun the same four-flow workflow against that immutable asset. The local source-built pass is not release provenance. |
| Product/nightly compatibility | Remaining collection, Trash, selector, and rename/move candidates must be promoted incrementally after the four-flow online gate. |
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
settings-search semantics failed on that historical APK. The online-only
one-fixture lane now passes locally against the current source-built independent
APK on API 35 ARM. The 2026-08-06 rerun recorded
`empty_login_attempts=1` and `seeded_login_attempts=1`, confirming that the
seeded-home readiness selector no longer needs the fallback retry. It remains
unproven against an immutable published asset and on the hosted x86_64 runner.
