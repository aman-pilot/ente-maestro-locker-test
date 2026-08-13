# Ente Locker Maestro tests

Maestro onboarding and end-to-end tests that run against published Ente Locker
Android builds.

At the start of every Android run, the workflows resolve the newest compatible
Locker beta or release-candidate APK from
[`ente/nightly`](https://github.com/ente/nightly/releases). They pin the exact
asset ID and SHA-256 digest for the run, then verify the APK before installing
it. The workflows do not build Locker or use Maestro Cloud.

The account-free onboarding workflow verifies first launch. The online workflow
runs on Ubuntu and starts an isolated Docker Compose stack with Museum,
PostgreSQL 15, MinIO, and a socat network bridge. It creates one synthetic
account, checks the empty state, applies one shared encrypted fixture, and runs
the ordered product flows against that same account without resetting the
backend.

The tests target published builds rather than a temporary Ente branch. Product
changes are therefore exercised after they reach Ente `main` and appear in a
compatible published APK.

Pull requests run only the workflows affected by their changed paths. Every
relevant push to `main` runs the complete hosted baseline, while manual runs can
target onboarding, the complete online lane, or one registered online flow.

See the [Locker test guide](docs/locker-test-rollout.md) for fixture ownership,
security boundaries, CI behavior, and deferred coverage.

## Run locally

Local Android runs require Docker, a rootable emulator with `sqlite3`, and
Maestro `2.6.1`. Resolve the APK immediately before each run so the helper pins
and verifies the exact published asset rather than trusting a reusable tag or
filename.

Run the repository checks:

```sh
scripts/check-static.sh
```

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

During a repair, run one registered online flow with `--only-flow <name>`.
After it passes, run the complete ordered lane before publishing shared flow,
fixture, runner, or workflow changes.

## Latest verified coverage

This is the post-run record of what is currently green.

### Hosted Android CI (published build)

The latest clean runs used the same published Locker asset on Android API 34
with Maestro `2.6.1`. The release tag is reusable, so the asset timestamp, ID,
and checksum identify the tested build precisely.

| Build detail | Verified value |
| --- | --- |
| APK | `ente-locker-v1.0.8.apk` (`locker-v1.0.8-rc`) |
| Asset created | 2026-08-05 12:56:34 UTC |
| Asset ID | `502622451` |
| SHA-256 | `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4` |

The clean required runs completed on 2026-08-11 UTC:
[online run 31477531786](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786),
[onboarding run 31474463061](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31474463061),
and [validation run 31477531800](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531800).
The online run completed 18 scenarios with zero failures using one account, one
fixture application, and zero backend resets. The onboarding run completed
onboarding with zero failures.

Every row below was verified by those exact authoritative `main` runs.

| Flow | Verified behavior |
| --- | --- |
| [`onboarding`](maestro/locker/onboarding/onboarding.yaml) | [![Passed: run 31474463061](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31474463061) Opens the published app from fresh state and completes account-free onboarding. |
| [`empty-home-and-save-options`](maestro/locker/online/empty-home-and-save-options.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Verifies the empty home state and available item types before fixture application. |
| [`empty-trash`](maestro/locker/online/empty-trash.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Verifies Trash is empty for the new account. |
| [`search-note-secret-and-thing`](maestro/locker/online/search-note-secret-and-thing.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Finds seeded note, secret, and real-world item records. |
| [`search-with-no-results`](maestro/locker/online/search-with-no-results.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Verifies the no-results search contract. |
| [`view-account-and-security-settings`](maestro/locker/online/view-account-and-security-settings.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Opens account and security settings without mutating sensitive data. |
| [`search-settings-and-open-account`](maestro/locker/online/search-settings-and-open-account.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Searches settings and opens the account surface. |
| [`view-about-and-support-settings`](maestro/locker/online/view-about-and-support-settings.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Verifies About and Help/Support rows without opening external links. |
| [`view-theme-options`](maestro/locker/online/view-theme-options.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Opens the theme selector and verifies the available choices. |
| [`change-language-and-restore-english`](maestro/locker/online/change-language-and-restore-english.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Changes the app language and restores English for later flows. |
| [`empty-collection`](maestro/locker/online/empty-collection.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Opens a seeded empty collection and verifies its complete empty state. |
| [`filter-items-by-collection`](maestro/locker/online/filter-items-by-collection.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Filters the home list by a seeded collection. |
| [`add-item-to-multiple-collections`](maestro/locker/online/add-item-to-multiple-collections.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Adds a seeded item to multiple collections and verifies membership. |
| [`mark-and-unmark-important`](maestro/locker/online/mark-and-unmark-important.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Toggles one seeded item in and out of Important. |
| [`select-all-and-mark-important`](maestro/locker/online/select-all-and-mark-important.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Selects a collection's items and applies the Important action. |
| [`bulk-add-delete-and-restore-items`](maestro/locker/online/bulk-add-delete-and-restore-items.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Adds two items to a collection, deletes them, verifies Trash, restores them, and verifies final membership. |
| [`delete-collection-keep-item`](maestro/locker/online/delete-collection-keep-item.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Deletes a collection while preserving its item in Uncategorized. |
| [`permanently-delete-note`](maestro/locker/online/permanently-delete-note.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Deletes a note and then permanently removes it from Trash. |
| [`logout`](maestro/locker/online/logout.yaml) | [![Passed: run 31477531786](https://img.shields.io/badge/Latest%20run-passed-2ea44f?style=flat-square&logo=githubactions&logoColor=white)](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31477531786) Logs out and verifies the signed-out screen. |

### Not yet green or intentionally deferred

- Eight core flows remain registered as `hostedUnresolved` until their
  published-build selectors and behavior pass targeted and complete-lane
  validation.
- Native document picker, preview, download, and platform/offline-state flows
  remain local or deferred.
- Public-link coverage requires a deliberate paid-product environment.
- Multi-account sharing roles, recovery, limits, and injected failures require
  separate environments.

Update this record from a clean complete `main` run, not a targeted or local
run. Keep historical failed and cancelled attempts in GitHub Actions rather
than accumulating debugging history here.
