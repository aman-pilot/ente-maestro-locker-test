# Locker normal-flow status

Verified locally on 2026-08-06 with Maestro 2.6.1, Android API 35 ARM, the
source-built independent Locker APK, one disposable online account, one shared
fixture application, and no intra-lane backend reset.

## Proven hosted lane (19 flows)

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
- `permanently-delete-note`
- `logout`

The evidence set is the latest clean combined run, in which 19 of 25 normal
flows passed, plus a later isolated green run for
`add-item-to-multiple-collections` (`1` test, `0` failures, 49 seconds). The
default hosted lane now contains only the flows with green evidence. A final
combined run of this narrowed 19-flow lane remains the next runtime gate; it was
not repeated while individual failures were being triaged.

## Normal flows deferred for targeted fixes

| Flow | Current blocker |
| --- | --- |
| `rename-and-delete-collections` | Collection selection/navigation is flaky: an earlier combined run passed, but isolated reruns did not expose the expected selection or collection action surface. |
| `edit-emergency-contact` | The seeded edit form did not expose an enabled Save action after the text change. |
| `create-uncategorized-secret` | Save remained disabled during the latest local run. |
| `create-uncategorized-thing` | Save remained disabled during the latest local run. |
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

The cursor-sync error seen once on the emulator has not reproduced after the
seeder reused and verified Locker's existing encrypted special-collection key.
Treat it as a blocker again only if it reappears in the narrowed end-to-end run.

No Flutter or Dart application change is currently required for the 19-flow
lane. The deferred failures are being held at the Maestro/fixture boundary
until an isolated run proves an application defect.
