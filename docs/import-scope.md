# Locker infrastructure import scope

Source snapshot: Ente revision `390eb68100b4cdc1a2a74e43e8c94a77ce17bc1e`
on 2026-08-03.

## Imported and aligned

- all 22 Locker fixture manifests;
- both public synthetic fixture files;
- all seven Rust seeder source modules plus regenerated Cargo metadata;
- Museum configuration and a new self-contained Compose stack;
- all 20 fixture profiles and 31 scenario-to-profile relationships;
- selector blockers, collection-action references, and historical result context;
- fixture, provenance, private-boundary, Cargo, Compose, and workflow static
  validation.

The Rust seeder was adapted so account assignment is external to `apply`. The
catalog was adapted so scenario knowledge is independent of product YAML and
does not declare a suite or account lifecycle.

## Intentionally not imported

- the 31 authenticated product Maestro YAML files;
- the private login prelude;
- suite lists and source-checkout inventory snapshots;
- runtime scripts whose control flow creates an account for every YAML run;
- YAML registration/count checks and platform-device runners;
- local run records, credentials, screenshots, logs, Cargo targets, or other
  ignored evidence.

These are omissions by design, not lost coverage. They depend on the final
account grouping, canonical YAML ownership, platform scope, and hosted shard
decisions.
