# Locker repository blocker status

Snapshot: 2026-08-03

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
| Premature account architecture | Catalog lifecycle is explicitly `unassigned`; `apply` consumes an external account context. |
| Premature product YAML import | The 31 scenario records retain fixture knowledge without importing their Maestro YAML. |

## Open decisions and runtime proofs

| Blocker | Required handling |
| --- | --- |
| Account lifecycle | Measure reset, reuse, grouping, parallelism, and failure isolation before choosing one account, grouped accounts, or separate accounts. |
| Hosted stack architecture | Repeat the pinned-stack proof on the eventual hosted x86 runner before enabling seeded CI. |
| Seeder runtime | Use a temporary private context to validate encrypted apply/read-back against representative profiles. |
| Product YAML ownership | Decide the import point and canonical edit location after lifecycle experiments. |
| Hosted x86 proof | Run the manual account-free workflow from the default branch after publication approval. |
| Product/nightly compatibility | Required collection, Trash, selector, and rename/move behavior must reach a published APK. |
| Native platform flows | Keep picker, viewer, download, and offline/network behavior outside the first hosted seeded gate. |

## Current evidence boundary

The account-free onboarding flow passed locally using Locker asset `499393890`
and Maestro 2.6.1 on an API 35 ARM emulator. The 25/26 counts retained under
catalog `historicalEvidence` came from the source prototype and do not prove
this repository, current manifests, current APK, or hosted execution.

No product YAML, login prelude, account credentials, run record, seeded runtime
workflow, or seeded-result artifact has been imported.
