# Ente Locker Maestro tests

Maestro smoke and end-to-end tests that run against Ente Locker Android builds.

The repository is proven independently before its Locker-owned paths are merged
beside Auth coverage in `aman-pilot/ente-maestro-tests`. Locker is online-only:
the authenticated lane starts a disposable Museum/PostgreSQL/MinIO stack,
creates one synthetic account, applies one shared E2EE fixture, and runs its
ordered product flows without replacing the account or resetting the backend.

Hosted Android workflows resolve one compatible Locker APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), pin the asset ID and
SHA-256 digest for the run, and use Maestro `2.6.1`. They do not build Locker or
use Maestro Cloud. The account-free smoke and authenticated seeded workflows
remain manual until the exact published APK passes the hosted x86_64 gate.
Static checks run on pull requests and pushes to `main`.

See the [Locker test rollout](docs/locker-test-rollout.md) for the local,
hosted, fixture, and deferred coverage boundaries.

## Run locally

Run the complete static gate first. It validates shell and YAML syntax,
workflow security, fixture/catalog integrity, provenance hashes, Cargo tests,
and Compose rendering without starting Docker or creating an account.

```sh
scripts/check-static.sh
```

Run account-free onboarding on one connected Android emulator:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-android-local.sh --apk "$apk_path" --suite onboarding
```

Run the authenticated online lane against an exact APK on a rootable emulator:

```sh
scripts/run-locker-seeded-suite.sh \
  --apk /absolute/path/to/locker.apk \
  --serial emulator-5554
```

The authenticated runner owns the disposable stack, app-data clearing, endpoint
configuration, same-account login, one fixture application, product-flow order,
credential redaction, and cleanup. Its public summary reports account, fixture,
reset, scenario, failure, identity, and login-attempt counts.

Maestro MCP is optional for local device inspection, screenshots, syntax checks,
and individual flow runs. The CLI runner remains the reproducible local and CI
gate.

## Latest verified coverage

This is the post-run record of what is currently green.

### Local Android online coverage

The latest clean authenticated run completed on 2026-08-06 using Android API 35
ARM64, Maestro `2.6.1`, and source-built independent APK SHA-256
`e71d456c9a571d293269c1c076912f7a8a124560f4d20a73803e5824e99b66f3`.
It created one account, applied one fixture, performed no backend resets, kept
the same account identity, and completed both empty and seeded login on their
first attempts.

| Flow | Verified behavior |
| --- | --- |
| Empty online account | Signs into the empty account and verifies the empty home plus Locker save options. |
| Seeded search | Applies the shared encrypted fixture once, clears only app data, signs back into the same account, and finds the expected note, secret, and thing. |
| Account and Security settings | Reuses the seeded session and verifies the synchronized Account and Security settings surfaces. |
| Settings search | Reuses the same backend state and opens Account through settings search semantics. |

### Hosted Android CI (published build)

The account-free onboarding flow passed hosted Android API 34 x86_64 against
`locker-v1.0.8-beta`, asset `500679355`, SHA-256
`1cd61604c67d93b5930c7b264fa35c54b54ed45da26b8203906af7e6e0b502d0`,
with Maestro `2.6.1`.

The authenticated four-flow lane has not yet been claimed green on hosted
x86_64 or against an immutable published Locker APK. The manual
`Locker Android seeded proof` workflow is the next release gate; once it passes,
record the exact run URL, APK asset ID, creation time, and digest here, following
the Auth README evidence format.

### Not yet green or intentionally deferred

- Repeat the four-flow authenticated proof against one exact published Locker
  APK on hosted Android API 34 x86_64.
- `rename-and-move-document` remains unresolved because Museum recorded the
  collection move while the renamed value was absent after save and relaunch.
- Native document picker/preview/download flows remain local platform work.
- Network/platform-state validation and the paid public-link flow remain
  deferred. Locker has no offline account mode.
- Expand the initial hosted lane only after the four-flow published-build gate
  is green; all 31 canonical product YAML files are already preserved.

## Runtime model

The initial authenticated lane is deliberately sequential:

1. Log into the empty online account and verify empty home.
2. Apply the shared search fixture once.
3. Clear app data, log back into the same account, and verify seeded search.
4. Reuse that session and backend state for the two settings flows.
5. Remove the disposable stack when the job ends.

There is no profile-per-flow account reset. Private credentials, account
contexts, Maestro login arguments, run records, and debug output remain outside
uploaded artifacts.

## Repository layout

| Path | Owns |
| --- | --- |
| `maestro/locker/smoke/` | Public account-free startup coverage. |
| `maestro/locker/online/` | Canonical authenticated product flows, matching Auth's online-flow layout. |
| `maestro/locker/online/subflows/` | Private runtime helpers such as same-account login; product YAML remains credential-free. |
| `maestro/locker/online/platform/`, `paid/` | Explicitly deferred platform-state and paid-product flows. |
| `locker/catalog.v1.json` | The single online fixture contract and preserved reference manifests. |
| `locker/product-flows.v1.json` | Canonical YAML provenance, classifications, and ordered online lane. |
| `locker/provenance.v1.json` | Ente revision, image digests, and fixture hashes. |
| `locker/manifests/` | The active online fixture plus preserved future fixture inputs. |
| `locker/fixtures/` | Public synthetic files used by document fixtures. |
| `locker/stack/` | Self-contained digest-pinned Museum/PostgreSQL/MinIO stack. |
| `tools/locker-seed/` | Rust manifest validation, account creation, E2EE seeding, and read-back verification. |
| `scripts/` | Static contracts, APK resolution, local execution, and the online lane runner. |
