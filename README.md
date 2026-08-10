# Ente Locker Maestro tests

Maestro smoke and end-to-end tests for published Ente Locker Android builds.

Locker is online-only. The authenticated lane starts an isolated
Museum/PostgreSQL/MinIO stack, creates one synthetic account, verifies the empty
state, applies one shared E2EE fixture, and runs the ordered product flows on
that same account without resetting the backend.

Android workflows resolve the newest compatible Locker APK from
[`ente/nightly`](https://github.com/ente/nightly/releases), pin its immutable
asset ID and SHA-256 digest, and use Maestro `2.6.1`. They do not compile Locker
or use Maestro Cloud. Static checks run on pull requests and pushes to `main`;
the Android workflows remain manual until the complete published-build lane is
green on hosted x86_64.

See the [Locker test guide](docs/locker-test-rollout.md) for fixture, ownership,
CI, and deferred-coverage contracts.

## Run locally

Run the complete non-Android gate first:

```sh
scripts/check-static.sh
```

Resolve and verify the current published APK, then run account-free onboarding:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-android-local.sh --apk "$apk_path" --suite onboarding
```

Run the authenticated online lane on a connected rootable emulator:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --apk "$apk_path" \
  --serial emulator-5554
```

While repairing one flow, run only that canonical YAML:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-seeded-suite.sh \
  --only-flow view-collection-and-item-action-menus \
  --apk "$apk_path" \
  --serial emulator-5554
```

The seeded runner owns the disposable stack, private login, app-data clearing,
single fixture application, ordered product execution, credential redaction,
JUnit output, and cleanup. Maestro MCP is optional for local inspection; the
CLI runner is the reproducible local and hosted entrypoint.

The manual hosted workflow accepts `flow=all` for the complete lane or one
registered hosted/unresolved flow name for a targeted x86_64 proof. Use the
targeted scope while iterating, then run `all` for promotion evidence.

## Latest verified coverage

### Local Android online lane

The latest clean full run completed on 2026-08-10 with Android API 35 ARM64 and
the following exact Ente GitHub release-candidate APK. Locker was not built
locally.

| Release | Asset ID | Build | SHA-256 |
| --- | --- | --- | --- |
| `locker-v1.0.8-rc` | `502622451` | `ente-locker-v1.0.8.apk` | `a5b8bc958ff71a2a310a2759811577179de3abe3ab10a157082a7e927b85bec4` |

All 20 default-lane flows passed in one ordered execution: 20 JUnit tests, no
failures, one account, one fixture application, no backend reset, unchanged
identity, and one successful empty-state login plus one seeded login.
Subsequent fixes to the search and collection-action readiness contracts each
passed targeted local runs against the same immutable APK.

### Hosted Android CI

Account-free onboarding is green on Android API 34 x86_64 against published
asset `500679355` with SHA-256
`1cd61604c67d93b5930c7b264fa35c54b54ed45da26b8203906af7e6e0b502d0`.

The latest completed authenticated attempt used Android API 34 x86_64 and exact
asset `502622451`. It passed the first 11 ordered flows before
`view-collection-and-item-action-menus` failed to enter `Home Inventory`
([run 31387905140](https://github.com/aman-pilot/ente-maestro-locker-test/actions/runs/31387905140)).
That flow now enters Collections through the drawer route already proven by the
hosted `empty-collection` flow instead of navigating through the filter sheet.

### Deferred coverage

- Six core flows remain classified as hosted-unresolved in
  `locker/product-flows.v1.json`.
- Native picker, preview, download, and offline/platform-state flows remain
  local or deferred.
- Public-link coverage requires a deliberate paid-product environment.
- Sharing roles, multi-account behavior, fault injection, and recovery remain
  outside the current single-account lane.

All 31 canonical product YAML files remain in this repository. Update this
section only from exact-asset evidence; keep historical failed runs in GitHub
Actions rather than adding debugging history to the README.
