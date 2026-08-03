# Seeded Locker runtime decisions

The standalone repository now contains the non-YAML parts of the Locker seeded
prototype: 22 manifests, 20 fixture profiles, 31 scenario records, public
synthetic fixture files, the Rust E2EE seeder, and a self-contained backend
stack.

## Decisions already made

- Product Maestro YAML stays out of this phase.
- Fixture profiles describe exact required starting inventory, not account
  ownership or reuse.
- `locker-seed apply` consumes a caller-supplied private account context.
- Account creation is an explicit local capability and is not wired into CI.
- Rust dependencies use one full Ente Git revision recorded in provenance.
- All backend images are digest pinned and recorded in provenance.
- Private account contexts and run records never enter artifacts or source
  control.
- Imported pass/failure counts are historical evidence, not current coverage.

## Account lifecycle intentionally unassigned

We will choose the orchestration model only after measuring the standalone
stack and seeder. The candidates remain:

1. one reusable account with a proven reset-to-baseline operation;
2. one account per fixture profile or behavior shard;
3. separate accounts only for destructive scenario groups;
4. one account per scenario.

No candidate is preferred by the current code or catalog. The decision must
compare preparation time, reset reliability, destructive-state leakage,
parallel execution, failure diagnosis, and credential handling. Until then,
there is no seeded hosted workflow, login prelude, suite matrix, or promotion
claim.

## What must be proven next

1. `cargo test --locked` and `cargo check --locked` from a clean checkout.
2. Repeat the successful local stack startup on the eventual hosted x86 runner.
3. Manifest validation and encrypted read-back using a private temporary
   account context.
4. Preparation, reset, and replay timings for representative empty, document,
   collection-action, and Trash profiles.
5. A concrete grouping experiment before importing any product YAML.

## Known product/runtime boundary

The historical `rename-and-move-document` scenario remains unresolved: Museum
showed the document in the target collection, while the renamed title was not
reliably displayed after save and relaunch. That assertion should remain intact
when YAML is eventually imported. Native picker/viewer and paid public-link
coverage also stay outside the first hosted seeded gate.
