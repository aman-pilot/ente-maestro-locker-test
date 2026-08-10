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

Download and verify the same Ente GitHub nightly used by CI, then run the
authenticated online lane on a rootable emulator:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --apk "$apk_path" \
  --serial emulator-5554
```

While repairing one flow, run only that canonical YAML and leave the complete
lane for the final gate:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --only-flow add-item-to-multiple-collections \
  --apk "$apk_path" \
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

This is the post-run record of what is currently green. The exact per-flow list
and deferred blockers are maintained in
[Locker normal-flow status](docs/normal-flow-status.md).

### Local Android online coverage

The latest clean authenticated run completed on 2026-08-10 using Android API 35
ARM64 and Maestro `2.6.1`. The APK was downloaded from Ente GitHub and verified
before execution; Locker was not compiled locally.

| Release | Asset ID | Build | SHA-256 |
| --- | --- | --- | --- |
| `locker-v1.0.8-rc` | `502622451` | `ente-locker-v1.0.8.apk` | `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4` |

All 20 flows in the default lane passed in one ordered execution. The public
runner summary was:

```text
seeded_suite status=pass accounts_created=1 fixture_applies=1 backend_resets=0 scenarios=20 failures=0 identity_unchanged=true empty_login_attempts=1 seeded_login_attempts=1
```

The JUnit suites contained 20 tests and 0 failures. The badges below open the
canonical Locker-owned YAML used by that clean run.

| Flow group | Verified behavior |
| --- | --- |
| Empty account | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/empty-home-and-save-options.yaml) Verifies empty home save options and empty Trash before fixture application. |
| Seeded search | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/search-note-secret-and-thing.yaml) Finds synchronized note, secret, and thing data and verifies the no-results state. |
| Account and settings | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/view-account-and-security-settings.yaml) Opens Account and Security, searches Settings, covers About and Support, and views theme options. |
| Language and collection filters | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/change-language-and-restore-english.yaml) Changes and restores language, verifies an empty collection, and filters items by collection. |
| Collection and item actions | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/view-collection-and-item-action-menus.yaml) Opens action menus and adds one item to multiple collections. |
| Important actions | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/mark-and-unmark-important.yaml) Marks and unmarks one item, then selects all and marks the scoped selection Important. |
| Bulk lifecycle | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/bulk-add-delete-and-restore-items.yaml) Performs bulk collection mutation, Trash, and restore, then deletes a collection while retaining its item. |
| Emergency Contact | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/edit-emergency-contact.yaml) Edits and saves the Emergency Contact setting. |
| Permanent deletion and logout | [![Local API 35: passed](https://img.shields.io/badge/Local%20API%2035-passed-0969da?style=flat-square&logo=android&logoColor=white)](maestro/locker/online/permanently-delete-note.yaml) Permanently deletes the prepared note and logs out last. |

### Hosted Android CI (published build)

The account-free onboarding flow passed hosted Android API 34 x86_64 against
`locker-v1.0.8-beta`, asset `500679355`, SHA-256
`1cd61604c67d93b5930c7b264fa35c54b54ed45da26b8203906af7e6e0b502d0`,
with Maestro `2.6.1`.

The latest authenticated hosted attempt used Android API 34 x86_64 and Maestro
`2.6.1`. The reusable release tag is not sufficient provenance, so the exact
asset timestamp, ID, and digest are recorded below.

| Build name | Asset created | Asset ID | SHA-256 |
| --- | --- | --- | --- |
| `ente-locker-v1.0.8.apk` | 2026-08-05 12:56:34 UTC<br>2026-08-05 18:26:34 IST | `502622451` | `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4` |

The manual published-build proof completed on 2026-08-10 UTC
([run 31366400340](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31366400340)).
It is a historical failed diagnostic run, not a green badge: 6 of 20 flows
passed and 14 failed. The old runner continued after failures on one mutable
account, so later results included cascade noise. The current YAML handles the
published RC's older drawer/menu labels and avoids Home-recency assumptions;
the current runner stops after the first product failure. The repaired lane is
20/20 locally against this same immutable asset and awaits a new hosted run.

The historical run proves that the exact-asset resolver, checksum verification,
hosted emulator, disposable stack, account/fixture lifecycle, JUnit upload, and
cleanup execute on hosted x86_64. The repaired 20-flow product lane still needs
its new hosted result.

### Not yet green or intentionally deferred

- Repeat the locally green 20-flow immutable published-APK proof on hosted
  Android API 34 x86_64.
- Promote the five additional normal flows listed in
  [Locker normal-flow status](docs/normal-flow-status.md); they remain outside
  the default lane rather than blocking it.
- `rename-and-move-document` remains unresolved because Museum recorded the
  collection move while the renamed value was absent after save and relaunch.
- Native document picker/preview/download flows remain local platform work.
- Network/platform-state validation and the paid public-link flow remain
  deferred. Locker has no offline account mode.
- All 31 canonical product YAML files remain preserved even when a flow is not
  in the proven hosted lane.

Update this evidence from a clean complete run, not from a targeted debugging
run. Keep failed or cancelled GitHub runs visible; this section should describe
the latest clean result without hiding the debugging history.

## Runtime model

The authenticated lane is deliberately sequential:

1. Log into the empty online account and verify empty home.
2. Run all proven empty-account flows.
3. Apply the shared online fixture once.
4. Clear app data and log back into the same account.
5. Run the ordered seeded product flows, with logout last.
6. Remove the disposable stack when the job ends.

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
