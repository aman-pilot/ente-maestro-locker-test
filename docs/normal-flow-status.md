# Locker normal-flow status

Verified locally on 2026-08-10 with Maestro 2.6.1, Android API 35 ARM64, the
source-built independent Locker APK, one disposable online account, one shared
fixture application, and no intra-lane backend reset.

## Default seeded lane (20 flows)

- `empty-home-and-save-options`
- `empty-trash`
- `search-note-secret-and-thing`
- `search-with-no-results`
- `view-account-and-security-settings`
- `search-settings-and-open-account`
- `view-about-and-support-settings`
- `view-theme-options`
- `change-language-and-restore-english`
- `empty-collection`
- `filter-items-by-collection`
- `view-collection-and-item-action-menus`
- `add-item-to-multiple-collections`
- `mark-and-unmark-important`
- `select-all-and-mark-important`
- `bulk-add-delete-and-restore-items`
- `delete-collection-keep-item`
- `edit-emergency-contact`
- `permanently-delete-note`
- `logout`

All 20 flows passed together in one clean ordered execution against source-built
independent APK SHA-256
`e71d456c9a571d293269c1c076912f7a8a124560f4d20a73803e5824e99b66f3`.
The JUnit output contained 20 tests, 0 failures, and 627 seconds of Maestro
execution. The runner created one account, applied one fixture, performed no
backend reset, kept the same identity, and completed both cold logins on attempt
one. This is local evidence; hosted x86_64 and exact-published-APK proof remain
separate gates.

## Hosted published-build result

Manual run
[`31366400340`](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31366400340)
executed all 20 flows on Android API 34 x86_64 with Maestro 2.6.1 against exact
published asset `502622451`, SHA-256
`a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4`.
Six flows passed:

- `empty-home-and-save-options`
- `search-with-no-results`
- `filter-items-by-collection`
- `add-item-to-multiple-collections`
- `mark-and-unmark-important`
- `select-all-and-mark-important`

The remaining 14 failed. Nine require the canonical `Open navigation menu`
semantic that is absent from this published RC. Seeded search readiness,
collection action visibility, bulk item visibility, delete-collection item
retention, and Emergency Contact also differed from the source-built proof.
The account/fixture invariants remained valid: one account, one fixture
application, zero backend resets, unchanged identity, and both login boundaries
on attempt one. Treat this as hosted infrastructure proof and published-build
compatibility evidence, not a green product lane.

## Normal flows deferred for targeted fixes

| Flow | Current blocker |
| --- | --- |
| `rename-and-delete-collections` | Collection selection/navigation is flaky: an earlier combined run passed, but isolated reruns did not expose the expected selection or collection action surface. |
| `create-uncategorized-secret` | Creation succeeds, but the later `Uncategorized` filter selector is absent. |
| `create-uncategorized-thing` | Creation succeeds, but the later `Uncategorized` filter selector is absent. |
| `create-edit-move-delete-and-restore-secret` | Creation and collection-selection semantics still need an isolated green run. |
| `create-edit-move-delete-and-restore-thing` | Creation and collection-selection semantics still need an isolated green run. |

`rename-and-move-document` remains the previously classified unresolved core
flow: Museum recorded the collection move, but the renamed title was absent
after save and relaunch.

Targeted debugging remains available through:

```sh
scripts/run-locker-seeded-suite.sh \
  --only-flow <hosted-or-unresolved-flow> \
  --apk /absolute/path/to/app-independent-debug.apk \
  --serial emulator-5554
```

The cursor-sync error seen once on the emulator did not reproduce in the clean
20-flow end-to-end run after the seeder reused and verified Locker's existing
encrypted special-collection key. Treat it as a blocker again only if it
reappears.

No Flutter or Dart application change is currently required for the 20-flow
lane. The deferred failures are being held at the Maestro/fixture boundary
until an isolated run proves an application defect.
