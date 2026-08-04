# Locker infrastructure import scope

Source snapshot: untracked Locker prototype assets in `aman-pilot/ente`, based
on Ente revision `390eb68100b4cdc1a2a74e43e8c94a77ce17bc1e`, imported on
2026-08-04. The base revision pins Rust dependencies; it is not a false claim
that the untracked YAML or manifests existed in that commit.

## Imported and aligned

- all 22 Locker fixture manifests;
- both public synthetic fixture files;
- all eight Rust seeder source modules plus regenerated Cargo metadata;
- Museum configuration and a new self-contained Compose stack;
- all 20 fixture profiles and 31 scenario-to-profile relationships;
- all 31 product Maestro flows under the canonical `maestro/locker/online/`
  owner, with runtime `APP_ID` selection and no login or credentials;
- explicit hosted-candidate, unresolved, platform, and paid classifications;
- selector blockers, collection-action references, and historical result context;
- fixture, provenance, private-boundary, Cargo, Compose, and workflow static
  validation.

The Rust seeder was adapted so account creation is external to `apply`. The
catalog keeps scenario knowledge independent of product YAML and now declares
the orchestration invariant: one isolated run creates one synthetic account,
then resets and reuses that same identity for every profile.

The standalone implementation adds a backend baseline module, local and hosted
proof runners, an Auth-aligned private login prelude, and a manual exact-APK
seeded workflow. Product YAML stays credential-free and executes separately
from that private runtime prelude.

## Intentionally not imported

- the source prototype's private login prelude (a new bounded runtime-only
  prelude is authored here instead);
- suite lists and source-checkout inventory snapshots;
- historical runtime scripts whose control flow created an account for every
  YAML run; that behavior is noncanonical and explicitly rejected here;
- YAML registration/count checks and platform-device runners;
- local run records, credentials, screenshots, logs, Cargo targets, or other
  ignored evidence.

These are omissions by design, not lost coverage. Product YAML ownership is
closed in this repository. Flow-, profile-, shard-, retry-, and pool-specific
accounts remain outside the supported architecture.
