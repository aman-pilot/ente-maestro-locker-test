# Locker infrastructure import scope

Source snapshot: Ente revision `390eb68100b4cdc1a2a74e43e8c94a77ce17bc1e`
on 2026-08-03.

## Imported and aligned

- all 22 Locker fixture manifests;
- both public synthetic fixture files;
- all eight Rust seeder source modules plus regenerated Cargo metadata;
- Museum configuration and a new self-contained Compose stack;
- all 20 fixture profiles and 31 scenario-to-profile relationships;
- selector blockers, collection-action references, and historical result context;
- fixture, provenance, private-boundary, Cargo, Compose, and workflow static
  validation.

The Rust seeder was adapted so account creation is external to `apply`. The
catalog keeps scenario knowledge independent of product YAML and now declares
the orchestration invariant: one isolated run creates one synthetic account,
then resets and reuses that same identity for every profile.

The standalone implementation adds a backend baseline module and a local proof
runner. Neither imports product YAML or a login prelude.

## Intentionally not imported

- the 31 authenticated product Maestro YAML files;
- the private login prelude;
- suite lists and source-checkout inventory snapshots;
- historical runtime scripts whose control flow created an account for every
  YAML run; that behavior is noncanonical and explicitly rejected here;
- YAML registration/count checks and platform-device runners;
- local run records, credentials, screenshots, logs, Cargo targets, or other
  ignored evidence.

These are omissions by design, not lost coverage. Product YAML import depends
on a proven same-account reset, canonical YAML ownership, and platform scope.
It does not depend on account grouping: flow-, profile-, shard-, retry-, and
pool-specific accounts are outside the supported architecture.
