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
| Exact-APK product entry | The manual workflow resolves and verifies the exact published APK and produces leakage-scanned JUnit. |
| Source-built seeded visibility | The narrowed 19-flow lane has green local evidence on API 35 ARM with source-built independent APK SHA-256 `e71d456c9a571d293269c1c076912f7a8a124560f4d20a73803e5824e99b66f3`; the combined 19-flow rerun remains pending. |
| Source-built settings semantics | The source proof passed `Open navigation menu` and `Search settings` against the current Locker source build. |
| Published RC seeded visibility | Exact asset `502622451` (`locker-v1.0.8-rc`, SHA-256 `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4`) passed empty home and seeded search locally on API 35 ARM, with both login boundaries completing on attempt one. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Exact published seeded gate | Asset `502622451` contains the behavior needed for seeded search but not the `Open navigation menu` semantic needed by both settings flows. Publish a newer Locker APK containing the proven semantics change, rerun locally, then use the same immutable asset for hosted x86_64. |
| Product/nightly compatibility | Six normal flows remain targeted blockers, listed in `docs/normal-flow-status.md`; `rename-and-move-document` remains separately unresolved. |
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
one-fixture runner now owns a 19-flow proven lane against the current
source-built independent APK on API 35 ARM. Its evidence combines the latest
clean 19/25 execution with a later isolated Add-to pass; one final combined
19-flow rerun remains pending. The complete lane also remains unproven against
a compatible immutable published asset and on the hosted x86_64 runner.

The 2026-08-06 local compatibility run against immutable published asset
`502622451` passed empty home and seeded search, then failed both settings flows
at `Open navigation menu`. A hosted run was intentionally not started because
it would exercise the same known-incompatible APK.
