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

The catalog no longer maps scenarios to fixture profiles. Inactive manifests
are retained as reference inputs while unresolved canonical flows are reworked
to reuse the shared fixture or create their own uniquely named data.

## Default seeded lane

The lane runs:

1. The two proven empty-account flows.
2. Apply `manifests/hosted-online.json` once.
3. Clear app data and cold-login to the same account.
4. The ordered seeded flows in `locker/product-flows.v1.json`, ending in
   `logout`.

There is no PostgreSQL template capture, MinIO reset, or account restoration
between those flows. Backend state lives only for the duration of the job.
The 20 included flows and five targeted normal-flow blockers are listed in
[`normal-flow-status.md`](normal-flow-status.md).

## Expanding the lane

Future flow promotion must preserve the single-fixture model:

- run exact-empty assertions before seeding or destructive actions;
- reuse existing fixture items instead of creating duplicate visible names;
- scope global selection actions to a known collection;
- chain create, mutate, Trash, restore, and permanent-delete phases in order;
- use unique names for data that is not intentionally shared;
- run logout last or explicitly cold-login afterward.

The 2026-08-10 source-APK evidence proves all 20 flows together in one clean
ordered run: 20 JUnit tests, 0 failures, one account, one fixture application,
no backend reset, unchanged identity, and both logins on attempt one. The shared login helper
accepts the stable seeded-home search semantic as well as the empty-home save
actions; a bounded same-account retry remains only as an observable
emulator/network fallback. The later release gate is to publish the needed app
semantics in one immutable APK and repeat the proof against that exact asset;
resetting the backend is not part of that validation.
