# Seeded Locker runtime decisions

The standalone repository contains all 31 canonical product YAML flows plus 22
manifests, 20 fixture profiles, public synthetic fixture files, the Rust E2EE
seeder, and a self-contained backend stack.

## Decisions already made

- Product Maestro YAML is canonical here and remains separate from private
  login orchestration.
- Fixture profiles describe exact required starting inventory.
- `locker-seed apply` consumes a caller-supplied private account context.
- Account creation is invoked only by the audited isolated runner, exactly once
  per local or manual hosted job.
- Each isolated seeded run creates exactly one temporary synthetic account.
- Every profile and scenario in that run reuses the same email, credentials,
  and user ID after a deterministic reset.
- A reset failure aborts the run; it never creates or selects another account.
- Rust dependencies use one full Ente Git revision recorded in provenance.
- All backend images are digest pinned and recorded in provenance.
- Private account contexts and run records never enter artifacts or source
  control.
- Imported pass/failure counts are historical evidence, not current coverage.

## Single-account-per-run contract

The account lifecycle decision is closed. One isolated local or hosted run
creates one synthetic account before executing seeded profiles. The account is
reset to the required deterministic baseline before each scenario, and its
email, credentials, and user ID remain unchanged for the entire run.

A separate CI job may create another synthetic account only because that job
starts a separately isolated backend stack. This job boundary is not a flow,
profile, retry, or shard boundary. Account pools, behavior-shard accounts,
profile-specific accounts, and fallback accounts after a reset failure are not
supported architectures.

## Selected reset: backend account baseline

API cleanup was rejected after auditing the pinned Ente revision. File,
collection, membership, and Trash deletion APIs retain tombstones and diff
history. Permanent file deletion marks objects for an asynchronous queue, so a
successful API response can still leave encrypted documents and thumbnails in
MinIO. Recreating `Important` or `Uncategorized` would also produce new IDs
while leaving earlier collection history.

The dedicated runtime therefore captures a PostgreSQL template database after
the account is created and its raw collection/Trash diffs and MinIO buckets are
confirmed empty. Before the next profile, `locker-seed reset`:

1. Stops Museum and socat.
2. Drops and recreates `ente_db` from `locker_account_baseline`.
3. Removes objects, versions, delete markers, and incomplete uploads from all
   three dedicated MinIO buckets.
4. Compares canonical per-table row/count hashes and all sequence values with
   the captured baseline.
5. Starts Museum and socat, logs in again, verifies the original user ID, and
   rejects any raw collection or Trash record or MinIO object.
6. Stops Museum again and performs a second fingerprinted restore so the SRP
   verification session/token rows are not handed to the next profile, then
   restarts Museum without another login.

PostgreSQL and MinIO cannot be restored atomically. If either operation or its
verification fails, Museum remains stopped and the run aborts; there is no
fallback account. The runner's trap then removes only its uniquely named
Compose project and volumes. The private baseline is bound to that explicit
project and a fingerprint of its container IDs, volume mounts, service labels,
and loopback port bindings. Its template fingerprint is verified before the
live database is dropped; new database connections are disabled and PostgreSQL
force-drops the old database to avoid the healthcheck race. Baseline metadata
is persisted while Museum remains stopped, and baseline commands accept only
the dedicated loopback endpoint.

This mechanism is deliberately limited to a dedicated local or CI backend. It
is more correct here than portable API cleanup because it removes diff history,
queues, sequence drift, documents, and thumbnails at the same boundary.

## Local proof

The clean local proof completed with exactly one account and four sequential
manifests. Three backend resets preserved the same redacted identity and each
reported zero collection records, Trash records, and MinIO objects before the
next apply. Trash ran before the final profile, so the third reset specifically
proved that raw Trash residue was removed. See `docs/single-account-proof.md`
for the redacted timing table.

## What remains

The static gate, hosted x86 stack/reset proof, canonical YAML import,
fail-closed Android orchestration, and exact-APK product entry are complete.
The manual four-flow hosted gate currently passes empty-home and
account/security, while seeded info fixtures remain invisible in the published
app and settings search lacks the canonical accessibility tooltip in that
asset. The next promotion input is a published Locker APK that fixes or
confirms both app-side contracts; then the same four-flow gate must be rerun
without weakening assertions. Native-system, platform/offline, paid, and
unresolved rename/move flows remain deferred.

## Known product/runtime boundary

The historical `rename-and-move-document` scenario remains unresolved: Museum
showed the document in the target collection, while the renamed title was not
reliably displayed after save and relaunch. That assertion should remain intact
when YAML is eventually imported. Native picker/viewer and paid public-link
coverage also stay outside the first hosted seeded gate.

Any older evidence produced by the source prototype is historical and
noncanonical. It may explain fixture or selector provenance, but it does not
prove reset correctness, account reuse, or current product coverage.
