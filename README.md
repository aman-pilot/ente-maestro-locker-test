# Ente Locker Maestro tests

Maestro smoke and end-to-end tests that run against published Ente Locker
Android builds.

At the start of every Android run, the workflows resolve the newest compatible
Locker beta or release-candidate APK from
[`ente/nightly`](https://github.com/ente/nightly/releases). The resolved asset
ID and SHA-256 digest are pinned for the run, and the downloaded APK is verified
before installation. The workflows do not build Locker or use Maestro Cloud.

The account-free smoke workflow verifies onboarding. The online workflow runs
on Ubuntu and starts an isolated Docker Compose stack containing Museum,
PostgreSQL 15, MinIO, and a socat network bridge. It creates one synthetic
account, verifies the empty state, applies one shared E2EE fixture, installs the
published APK once, connects the emulator with `adb reverse`, and executes the
ordered product flows without resetting the backend.

Pull requests run only workflows affected by their changed paths. Every
relevant push to `main` runs the complete hosted baseline. Manual runs can
target onboarding, the complete online lane, or one registered online flow.

| Workflow | Purpose |
| --- | --- |
| `Locker validation` | Static, provenance, fixture, selector, workflow-security, Rust, and shell contract checks. |
| `Locker Android smoke` | Account-free onboarding on Android API 34 x86_64. |
| `Locker Android online` | One-account, one-fixture online product lane on Android API 34 x86_64. |

See the [Locker test guide](docs/locker-test-rollout.md) for ownership,
fixtures, security boundaries, and deferred coverage.

## Run locally

Validate the repository before starting Android or Docker:

```sh
scripts/check-static.sh
```

Local Android runs require Docker, a rootable emulator with `sqlite3`, and
Maestro `2.6.1`. Resolve the APK immediately before a run so the helper records
and verifies the exact published asset rather than trusting a reusable tag or
filename.

Run account-free onboarding:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-android-local.sh --apk "$apk_path" --suite onboarding
```

Run the complete online lane:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --apk "$apk_path" \
  --serial emulator-5554
```

Run one registered online flow while repairing it:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --apk "$apk_path" \
  --serial emulator-5554 \
  --only-flow empty-collection
```

Docker images are pulled by default, matching CI. If Docker Desktop's registry
transaction stalls and every compose image is already cached at the exact
digest pinned in `locker/stack/compose.yaml`, a local run can use
`LOCKER_COMPOSE_PULL_POLICY=never`. Hosted CI always keeps the default `always`
policy.

The online runner owns stack creation and removal, private login, app-data
preparation, fixture application, JUnit output, credential-leak checks, and
failure diagnostics. Maestro MCP is optional for inspection; the CLI runner is
the reproducible local and hosted entrypoint.

Product assertions are never retried. The runner retries once only when JUnit
proves Maestro's Android driver became unavailable during `deviceInfo`, before
the product flow began; the redacted summary records that recovery as
`product_driver_retries`.

## Local-first change policy

To conserve hosted runner minutes, batch workflow, fixture, and flow changes
before pushing:

1. Run the smallest affected flow locally.
2. Run the complete 18-flow online lane when shared state or online CI changes.
3. Run `scripts/check-static.sh` and inspect the final Git diff.
4. Push the finished batch once, then use the resulting automatic `main` run as
   the hosted proof.

Do not promote a targeted run or a partial local result as complete-lane
evidence.

## Latest verified coverage

### Published build

The latest clean local online run completed on 2026-08-11 using Android API 34
ARM64 and Maestro `2.6.1`. This is the closest local equivalent of hosted CI;
GitHub uses Ubuntu x86_64 KVM while the local runner uses macOS ARM64. Both use
the same published APK, Docker backend, account/fixture runner, API level,
device profile, memory, and flow order.

| Build detail | Verified value |
| --- | --- |
| APK | `ente-locker-v1.0.8.apk` (`locker-v1.0.8-rc`) |
| Asset created | 2026-08-05 12:56:34 UTC |
| Asset ID | `502622451` |
| SHA-256 | `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4` |

The complete local run produced 18 JUnit tests with zero failures, one account,
one fixture application, zero backend resets, unchanged identity, one
empty-account login, and one seeded-account login.

### Hosted Android CI

These badges show the authoritative `main` status for the published-build
workflows:

| Lane | Status |
| --- | --- |
| Online | [![Locker Android online](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-android-online.yml/badge.svg?branch=main)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-android-online.yml) |
| Smoke | [![Locker Android smoke](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-android-smoke.yml/badge.svg?branch=main)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-android-smoke.yml) |
| Validation | [![Locker validation](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-static.yml/badge.svg?branch=main)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/workflows/locker-static.yml) |

### Online flow behavior

| Flow | Verified behavior |
| --- | --- |
| [`empty-home-and-save-options`](maestro/locker/online/empty-home-and-save-options.yaml) | Verifies the empty home state and available item types before fixture application. |
| [`empty-trash`](maestro/locker/online/empty-trash.yaml) | Verifies Trash is empty for the new account. |
| [`search-note-secret-and-thing`](maestro/locker/online/search-note-secret-and-thing.yaml) | Finds seeded note, secret, and real-world item records. |
| [`search-with-no-results`](maestro/locker/online/search-with-no-results.yaml) | Verifies the no-results search contract. |
| [`view-account-and-security-settings`](maestro/locker/online/view-account-and-security-settings.yaml) | Opens account and security settings without mutating sensitive data. |
| [`search-settings-and-open-account`](maestro/locker/online/search-settings-and-open-account.yaml) | Searches settings and opens the account surface. |
| [`view-about-and-support-settings`](maestro/locker/online/view-about-and-support-settings.yaml) | Verifies About and Help/Support rows without opening external links. |
| [`view-theme-options`](maestro/locker/online/view-theme-options.yaml) | Opens the theme selector and verifies available choices. |
| [`change-language-and-restore-english`](maestro/locker/online/change-language-and-restore-english.yaml) | Changes the app language and restores English for later flows. |
| [`empty-collection`](maestro/locker/online/empty-collection.yaml) | Opens a seeded empty collection and verifies its complete empty state. |
| [`filter-items-by-collection`](maestro/locker/online/filter-items-by-collection.yaml) | Filters the home list by a seeded collection. |
| [`add-item-to-multiple-collections`](maestro/locker/online/add-item-to-multiple-collections.yaml) | Adds a seeded item to multiple collections and verifies membership. |
| [`mark-and-unmark-important`](maestro/locker/online/mark-and-unmark-important.yaml) | Toggles one seeded item in and out of Important. |
| [`select-all-and-mark-important`](maestro/locker/online/select-all-and-mark-important.yaml) | Selects a collection's items and applies the Important action. |
| [`bulk-add-delete-and-restore-items`](maestro/locker/online/bulk-add-delete-and-restore-items.yaml) | Adds two items to a collection, deletes them, verifies Trash, restores them, and verifies final membership. |
| [`delete-collection-keep-item`](maestro/locker/online/delete-collection-keep-item.yaml) | Deletes a collection while preserving its item in Uncategorized. |
| [`permanently-delete-note`](maestro/locker/online/permanently-delete-note.yaml) | Deletes a note and then permanently removes it from Trash. |
| [`logout`](maestro/locker/online/logout.yaml) | Logs out and verifies the signed-out screen. |

### Not yet green or intentionally deferred

- Eight core flows remain registered as `hostedUnresolved` until their
  published-build selectors and behavior pass both targeted and complete-lane
  validation.
- Native document picker, preview, download, and platform/offline-state flows
  remain local or deferred.
- Public-link coverage requires a deliberate paid-product environment.
- Multi-account sharing roles, recovery, limits, and injected failures require
  separate environments.

All 31 canonical product YAML files remain versioned. Update verified coverage
from a clean complete run; keep historical failed and cancelled attempts in
GitHub Actions rather than accumulating debugging history here.
