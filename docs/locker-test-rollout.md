# Locker Maestro test guide

This repository verifies published Ente Locker Android beta and
release-candidate APKs. It is not an Ente checkout and does not build the app.

The [README coverage record](../README.md#latest-verified-coverage) describes
the latest exact-asset evidence. Keep one-off debugging notes and historical
failure analysis in GitHub Actions or the relevant product issue so this guide
stays current.

## Test layers

| Layer | Purpose | Runs in hosted CI |
| --- | --- | --- |
| Published smoke | Account-free onboarding and startup behavior. | Yes, through the manual smoke workflow. |
| Online product lane | Empty-state and seeded Locker behavior on one disposable account. | Yes, through the manual seeded workflow. |
| Platform local | Native picker, preview, download, share, and device-state behavior. | No; validate on a local emulator or device. |
| Future environments | Paid public links, sharing roles, recovery, limits, and injected failures. | No. |

## Nightly and fixture contract

Every Android run resolves the newest compatible published Locker APK with
`scripts/resolve-nightly-apk.sh --app locker`. Beta and release-candidate tags
are eligible. Because tags can be reused, the resolver orders APK assets by
creation time and records the exact asset ID, filename, timestamp, and SHA-256.
The job downloads that asset ID and verifies its digest before installation.

The suite does not follow temporary Ente branches. A product change becomes a
test target after it reaches Ente `main` and appears in a compatible published
APK. Building the repository-owned Rust seeder is allowed; building Locker is
not.

Each authenticated run owns one isolated Museum/PostgreSQL/MinIO stack and one
synthetic account. It runs empty-account checks first, applies
`locker/manifests/hosted-online.json` once, clears Android app data, logs back
into the same account, and executes the ordered seeded flows. It does not reset
the backend or create another account between flows. App-data clearing is only
a cold-client boundary and does not change backend state.

Credentials, account contexts, Maestro login arguments, run records, raw UI
hierarchies, and debug output stay private. Product YAML must not contain login
data or backend endpoints. On the known collection-entry assertion failure, the
runner may publish one leakage-scanned route probe derived from the private
hierarchy; it contains only a structural page classification, action count, and
fixed booleans for the known seeded collection row, collection title, and item
title. A fixed capture status reports hierarchy-command, timeout, or parser
failure without exposing raw UI text.
The runner stops after the first product failure because later flows share
mutable state and would otherwise produce cascade noise.

## Repository layout

| Path | Owns |
| --- | --- |
| `maestro/locker/smoke/` | Public account-free flows. |
| `maestro/locker/online/` | Canonical authenticated product flows. |
| `maestro/locker/online/subflows/` | Private runtime and shared online helpers. |
| `maestro/locker/online/platform/`, `paid/` | Explicitly deferred platform and paid flows. |
| `locker/product-flows.v1.json` | Canonical YAML inventory, classifications, and lane order. |
| `locker/catalog.v1.json` | Active fixture contract and preserved reference manifests. |
| `locker/manifests/`, `locker/fixtures/` | Shared encrypted fixture input and public files. |
| `locker/stack/`, `tools/locker-seed/` | Disposable backend and E2EE account/fixture seeder. |
| `scripts/`, `.github/workflows/` | Static checks, APK resolution, local runners, and hosted jobs. |

The top-level `locker/` directory is not a second Maestro tree. It owns fixture
and runtime infrastructure; `maestro/locker/` owns executable UI flows.

## Adding or changing a test

1. Put account-free flows under `maestro/locker/smoke/` and authenticated
   product flows under `maestro/locker/online/`.
2. Use `appId: ${APP_ID}` and keep product YAML free of credentials, endpoint
   setup, `clearState`, and app-specific orchestration.
3. Prefer a shipped accessibility identifier, then a visible user-facing
   label. Use coordinates only when a published build exposes neither.
4. Wait for meaningful product state such as seeded content, a sheet title, or
   an action label. Do not add blanket retries or arbitrary sleeps.
5. Register the flow in the relevant selector or in
   `locker/product-flows.v1.json`; static validation rejects orphaned YAML and
   stale canonical hashes.
6. Run the smallest relevant Android flow, then `scripts/check-static.sh`.
   Run the complete ordered lane only after targeted failures are repaired.

Preserve unique fixture names because Maestro-visible labels are part of the
contract. Add reusable subflows only for small, stable interactions; do not use
them to hide product state or account lifecycle.

## Hosted CI behavior

Static checks run on pull requests and pushes to `main`. Android workflows are
manual while the published x86_64 baseline is being proven. Shared workflows,
selectors, fixtures, and runtime helpers select or invalidate the complete
relevant lane; platform-local paths intentionally select no hosted suite.

The seeded workflow accepts `flow=all` or one registered hosted/unresolved flow
name. A targeted run keeps the same disposable stack, account, fixture, login,
APK, and leakage controls while executing only the selected product YAML. Use
it to verify an x86_64-specific repair before spending time on the complete
ordered lane; targeted evidence does not promote the full lane.

External actions, Docker images, Rust dependencies, and Maestro are pinned.
Hosted summaries record immutable APK provenance and public lifecycle counts.
Authenticated artifacts contain leakage-scanned JUnit, the redacted lifecycle
summary, and at most one structural product-failure route probe. Login and
private-run diagnostics remain private; account-free smoke may retain Maestro
diagnostics.

## Intentional exclusions

- Six core flows are preserved but remain hosted-unresolved until their
  published-build semantics pass targeted and complete-lane validation.
- Native document picker, preview, download, and platform/offline-state flows
  are not part of the first hosted lane.
- Paid public links, multi-account sharing roles, recovery, limits, and fault
  injection require separate environments and are deferred.
- Locker has no offline-account mode.

## Promoting coverage

Promote a flow only when it uses deterministic published-build selectors,
preserves the one-account/one-fixture contract, keeps diagnostics secret-free,
and passes the exact published APK in its required environment. Update README
coverage from a clean complete `main` run, not a targeted run or local result
presented as hosted evidence.

Catalog `historicalEvidence` is noncanonical import context. It cannot promote
coverage or replace current JUnit and runner-summary evidence.
