# Ente Locker Maestro tests

Standalone Maestro infrastructure for published Ente Locker Android builds.
The repository is proven independently before its Locker-owned paths are merged
beside Auth coverage in `aman-pilot/ente-maestro-tests`.

## Current scope

Locker is an online-only product in this repository. The authenticated runtime
uses one disposable backend stack, one synthetic account, and one shared E2EE
fixture application per lane. Product flows reuse that backend state in a
deliberate order; there is no profile-per-flow account reset.

The repository owns all 31 canonical product YAML flows: 25 hosted candidates,
one unresolved online flow, three native-system flows, one platform-state
validation flow, and one paid flow. Native, paid, and network-state validation
remain deferred; Locker itself has no offline account mode.

The initial hosted lane is intentionally small:

1. Log into the empty online account and verify empty home.
2. Apply the shared search fixture once.
3. Clear app data, log back into the same account, and verify seeded search.
4. Reuse that session and backend state for the two settings flows.
5. Remove the entire disposable stack when the job ends.

## Repository layout

| Path | Owns |
| --- | --- |
| `locker/catalog.v1.json` | The single online fixture contract and preserved reference manifests. |
| `locker/product-flows.v1.json` | Canonical YAML provenance, classifications, and ordered online lane. |
| `locker/provenance.v1.json` | Ente revision, image digests, and fixture hashes. |
| `locker/manifests/` | The active online fixture plus preserved future fixture inputs. |
| `locker/fixtures/` | Public synthetic files used by document fixtures. |
| `locker/stack/` | Self-contained digest-pinned Museum/PostgreSQL/MinIO stack. |
| `tools/locker-seed/` | Rust manifest validation, account creation, E2EE seeding, and read-back verification. |
| `maestro/locker/smoke/` | Public account-free startup coverage. |
| `maestro/locker/online/` | Canonical authenticated product flows, matching Auth's online-flow layout. |
| `maestro/locker/online/subflows/` | Private runtime helpers such as same-account online login; product YAML remains credential-free. |
| `maestro/locker/online/platform/`, `paid/` | Explicitly deferred platform-state and paid-product flows. |
| `scripts/` | Static contracts, APK resolution, local execution, and the online lane runner. |

## Validate locally

The complete static gate validates shell and YAML syntax, workflow security,
fixture/catalog integrity, provenance hashes, Cargo tests, and Compose rendering.
It does not start Docker, create an account, or run Maestro.

```sh
scripts/check-static.sh
```

Validate the active online fixture directly:

```sh
cargo run --manifest-path tools/locker-seed/Cargo.toml -- \
  validate --manifest locker/manifests/search-note-secret-and-thing.json
```

Run account-free onboarding on one connected Android device:

```sh
apk_path=$(scripts/download-locker-nightly.sh)
scripts/run-locker-android-local.sh --apk "$apk_path" --suite onboarding
```

The authenticated hosted workflow calls
`scripts/run-locker-seeded-suite.sh`. Private credentials, account contexts,
Maestro login arguments, run records, and debug output remain outside uploaded
artifacts.

## Verification status

The account-free onboarding flow passed hosted API 34 x86_64 against
`locker-v1.0.8-beta`, asset `500679355`, SHA-256
`1cd61604c67d93b5930c7b264fa35c54b54ed45da26b8203906af7e6e0b502d0`,
with Maestro 2.6.1.

The online-only four-flow lane passes locally on API 35 ARM against source-built
independent APK SHA-256
`e71d456c9a571d293269c1c076912f7a8a124560f4d20a73803e5824e99b66f3`.
It proves one account, one shared fixture application, seeded search, account
and security settings, and settings-search semantics without a backend reset.
The remaining release gate is to repeat that proof against one immutable
published APK and on the hosted x86_64 runner.
