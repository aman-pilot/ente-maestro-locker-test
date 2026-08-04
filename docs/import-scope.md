# Locker infrastructure import scope

Source snapshot: untracked Locker prototype assets in `aman-pilot/ente`, based
on Ente revision `390eb68100b4cdc1a2a74e43e8c94a77ce17bc1e`, imported on
2026-08-04. The base revision pins Rust dependencies; it is not a false claim
that the untracked YAML or manifests existed in that commit.

## Imported and aligned

- all 22 Locker fixture manifests;
- both public synthetic fixture files;
- the Rust E2EE seeder plus regenerated Cargo metadata;
- Museum configuration and a new self-contained Compose stack;
- one active online fixture contract, with the remaining manifests preserved as
  future reference inputs;
- all 31 product Maestro flows under the canonical `maestro/locker/online/`
  owner, with runtime `APP_ID` selection and no login or credentials;
- explicit hosted-candidate, unresolved, platform, and paid classifications;
- selector blockers, collection-action references, and historical result context;
- fixture, provenance, private-boundary, Cargo, Compose, and workflow static
  validation.

The Rust seeder keeps account creation external to `apply`. The catalog now
declares one online account and one shared fixture application for the ordered
lane; it contains no scenario-to-profile mapping.

The standalone implementation adds an Auth-aligned private login prelude and a
manual exact-APK online workflow. Product YAML stays credential-free and
executes separately from that private runtime prelude.

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
closed in this repository. Flow-, shard-, retry-, and pool-specific accounts
remain outside the supported architecture.
