# Locker repository blocker status

Snapshot: 2026-08-10

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
| Local exact published seeded gate | Exact asset `502622451` (`locker-v1.0.8-rc`, SHA-256 `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4`) passed all 20 ordered flows locally on API 35 ARM64: one account, one fixture application, no backend reset, unchanged identity, and both cold logins on attempt one. |
| Published-build semantic compatibility | A shared drawer helper prefers current accessibility semantics and uses a stable header fallback for the older RC; settings labels accept both published and current forms. Home recency is no longer treated as a complete inventory. |
| Failure isolation | The seeded runner stops after the first product failure because later dependent results on the same mutable account would be cascade noise. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Hosted exact published seeded gate | Repeat the locally green 20-flow asset `502622451` proof on API 34 x86_64. Historical run `31366400340` predates the compatibility and fail-fast repairs. |
| Additional flow promotion | Five normal flows remain outside the default lane, listed in `docs/normal-flow-status.md`; `rename-and-move-document` remains separately unresolved. |
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
one-fixture runner now owns a 20-flow proven lane against exact published asset
`502622451` on API 35 ARM64. On 2026-08-10 all 20 flows passed together with
zero failures while preserving the account and fixture contract. The complete
lane remains unproven only on the hosted x86_64 runner.

The 2026-08-06 local compatibility run against immutable published asset
`502622451` passed empty home and seeded search, then failed both settings flows
at `Open navigation menu`. A hosted run was initially deferred because it would
exercise the same known-incompatible YAML/APK pairing. Requested run
`31366400340` later recorded 6 of 20 passes and 14 failures on API 34 x86_64.
That revision lacked published-build selector fallbacks and continued dependent
flows after a failure, so it remains infrastructure history rather than the
current product result. Account creation, fixture application, identity
preservation, result upload, and cleanup all completed correctly.
