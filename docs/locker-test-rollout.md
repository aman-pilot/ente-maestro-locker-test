# Locker Maestro rollout guide

This repository verifies published Ente Locker Android beta and
release-candidate APKs. It is not an Ente checkout and does not build the app.

## Test layers

| Layer | Purpose | Current state |
| --- | --- | --- |
| Published smoke | Account-free onboarding and other public startup behavior. | Hosted API 34 x86_64 proof passed. |
| Online product lane | One synthetic online account and one shared encrypted fixture per isolated run, with no intra-lane backend reset. | Source-built API 35 ARM proof passed; exact published-APK hosted proof remains. |
| Platform local | Native picker, viewer, download, share, and other OS behavior. | Deferred from hosted CI. |
| Multi-account and fault | Sharing roles, recovery, limits, and injected backend/device failures. | Deferred. |

## Nightly contract

Every run resolves the newest compatible published Locker APK at workflow
start using `scripts/resolve-nightly-apk.sh --app locker`. Beta and
release-candidate tags are eligible. Because release tags can be reused, assets
are ordered by creation time and the exact asset ID and digest are passed to
every selected job.

The repository does not follow temporary Ente branches. A product change
becomes a hosted test target only after it reaches Ente `main` and is present
in a compatible published Locker nightly.

## Adding an account-free flow

1. Put the flow under `maestro/locker/smoke/`.
2. Use `appId: ${APP_ID}` so local and hosted runners can select the published
   independent application ID without rewriting YAML.
3. Prefer shipped semantics identifiers, then visible labels. Do not add
   coordinates when the product can expose a stable accessible control.
4. Wait for a meaningful screen state rather than using arbitrary sleeps.
5. Register the flow in `scripts/select-locker-ci-suites.sh`.
6. Extend `scripts/test-select-locker-ci-suites.sh` when a new suite or mapping
   is added.
7. Run `scripts/check-static.sh`.

Authenticated product flows live under `maestro/locker/online/` and are
classified by `locker/product-flows.v1.json`. They intentionally contain no
login, endpoint, or credential setup. Their runner must create one account
before the suite, apply the shared fixture once, and preserve that identity and
backend state across the ordered lane.

Like Auth, shared online orchestration lives under
`maestro/locker/online/subflows/`. The top-level `locker/` directory is not a
second Maestro tree: it owns Locker-only manifests, public fixture inputs,
catalog/provenance, and the disposable backend stack.

Registration validation fails when a smoke flow is not reachable from a
selected hosted suite. Shared helpers should remain small and must not escape
the `maestro/locker/` hierarchy.

## Hosted behavior

Static checks run on pull requests and pushes to `main`. The Android workflow
is manual during bootstrap. After one clean default-branch x86 run proves the
published-nightly contract, the changed-path selector is ready to support
targeted pull-request execution and a complete relevant baseline on `main`.

Changes to shared helpers, workflows, selectors, or nightly resolution select
the full Locker matrix. Platform-local paths intentionally select no hosted
suite.

An online job creates one synthetic account because it owns one fresh, isolated
backend stack. It applies the shared fixture once and reuses the account and
backend state for every ordered flow. A different job owns a different
disposable stack; flow, retry, and shard account assignment remain unsupported.

The workflow pins external actions and Maestro to immutable revisions, records
APK provenance in the job summary, uploads JUnit output for seven days, and
retains account-free smoke diagnostics on failure.

When switching between locally installed Maestro versions on a reused emulator,
a driver startup timeout can come from stale `dev.mobile.maestro` packages.
Remove `dev.mobile.maestro` and `dev.mobile.maestro.test`, then retry before
classifying the result as a Locker failure. Hosted jobs start from fresh
emulators and should not retain this state.

## Promotion rule

Do not describe a flow as hosted-verified from a local run, a targeted pull
request run, or an unmerged branch. Update public coverage only from a clean
complete run on the default branch using an exact recorded APK digest.

Catalog `historicalEvidence` is noncanonical import context. It may guide later
assertion work but cannot promote seeded coverage or prove single-account reuse.

The retired reset proof is historical infrastructure evidence, not product
coverage for the online-only lane. Product promotion requires the one-fixture
runner, private login only at cold-client boundaries, credential-free product
invocations, and an exact published APK run.
