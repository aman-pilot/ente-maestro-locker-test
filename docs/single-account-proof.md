# Locker single-account reset proof

Verified locally on 2026-08-03 against the repository's digest-pinned
Museum/PostgreSQL/MinIO/socat stack.

## Result

The proof created exactly one synthetic account and reused the same redacted
identity for all four fixture profiles:

1. `search-note-secret-and-thing.json`
2. `document.json`
3. `trash.json`
4. `add-item-to-multiple-collections.json`

The first profile covered Note, Secret, and Thing encrypted payloads. The
second uploaded and downloaded/decrypted both a document and thumbnail. The
third verified Trash state and was itself removed by the next backend reset.
The fourth verified one item in multiple encrypted collections on that clean
post-Trash baseline.

Every reset reported:

- the same redacted account identity;
- an exact PostgreSQL logical fingerprint matching the captured template;
- zero raw collection records, including deleted collection tombstones;
- zero raw Trash records, including deleted or restored entries;
- zero MinIO objects, versions, delete markers, or incomplete uploads.

The cleanup trap removed the private temporary directory and the uniquely
named Compose project's containers, network, and volumes. Console output and
this record contain no email, password, token, user ID, or private path.

## Final timing evidence

| Phase | Profile | Duration |
| --- | --- | ---: |
| Stack startup | - | 16.064s |
| Account creation | - | 32.052s |
| Baseline capture | - | 34.658s |
| Apply and decrypt-verify | Search structured items | 31.791s |
| Inspection | Search structured items | 31.625s |
| Reset | Search structured items | 37.932s |
| Apply and decrypt-verify | Document and thumbnail | 30.972s |
| Inspection | Document and thumbnail | 32.725s |
| Reset | Document and thumbnail | 43.408s |
| Apply and decrypt-verify | Trash | 40.913s |
| Inspection | Trash | 32.349s |
| Reset | Trash | 38.031s |
| Apply and decrypt-verify | Multiple memberships | 31.577s |
| Inspection | Multiple memberships | 31.354s |
| Final cleanup | - | 1.020s |

The measured phase total was 466.471s, or approximately 7m 46s. Average reset
time was 39.790s. These are local measurements, not hosted x86 estimates.

## Failure behavior

Reset stops Museum before replacing PostgreSQL and clearing MinIO. If database
recreation, object cleanup, fingerprint verification, or empty-state
verification fails, the command exits nonzero and does not create another
account. Each baseline is bound to a fingerprint of the runner's unique
Compose project, container IDs, volume mounts, service labels, and loopback
port bindings. The template fingerprint is checked before `ente_db` is
replaced, and only the fixed loopback Museum endpoint is accepted. The runner
emits only a redacted failure category and its exit trap removes the dedicated
Compose project and private temporary directory.

The mocked runner test separately proves that account creation is invoked once,
all four manifests are attempted in sequence, three resets occur, private
output is not printed, and cleanup still runs after a mid-sequence apply
failure.

## Coverage boundary

This is seeder and reset evidence. It does not claim that any authenticated
product Maestro YAML has run in this repository. Product YAML, login helpers,
and a seeded hosted workflow remain intentionally absent.
