# Online Locker runtime decisions

Locker uses one online test lane. There is no offline-account test mode and no
fixture profile assigned per flow.

## Runtime contract

- One disposable Museum/PostgreSQL/MinIO stack is created per isolated job.
- One synthetic online account is created exactly once in that stack.
- Product YAML stays credential-free; private login remains a separate runtime
  invocation.
- The account starts empty so empty-home behavior can run first.
- One shared E2EE fixture is applied exactly once before the first seeded flow.
- Android app data is cleared only at cold-login boundaries. `pm clear` does not
  reset backend state.
- Later flows reuse the same account, fixture, and backend mutations in a
  deliberate order.
- The complete disposable stack is removed at job completion.

The catalog no longer maps scenarios to fixture profiles. The 21 inactive
manifests are retained as reference inputs while later canonical flows are
reworked to reuse the shared fixture or create their own uniquely named data.

## Initial hosted lane

The first lane runs:

1. `empty-home-and-save-options` on the empty account.
2. Apply `manifests/search-note-secret-and-thing.json` once.
3. Clear app data and cold-login to the same account.
4. `search-note-secret-and-thing`.
5. `view-account-and-security-settings`.
6. `search-settings-and-open-account`.

There is no PostgreSQL template capture, MinIO reset, or account restoration
between those flows. Backend state lives only for the duration of the job.

## Expanding the lane

Future flow promotion must preserve the single-fixture model:

- run exact-empty assertions before seeding or destructive actions;
- reuse existing fixture items instead of creating duplicate visible names;
- scope global selection actions to a known collection;
- chain create, mutate, Trash, restore, and permanent-delete phases in order;
- use unique names for data that is not intentionally shared;
- run logout last or explicitly cold-login afterward.

The current source-built independent APK passes the complete four-flow lane,
including seeded collection/file visibility and settings-search semantics. The
remaining release gate is to publish those app changes in one immutable APK and
repeat the proof against that exact asset; resetting the backend is not part of
that validation.
