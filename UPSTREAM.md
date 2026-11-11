# Upstream source

The application code in `src/` comes from Google's Bank of Anthos sample:

- Repository: https://github.com/GoogleCloudPlatform/bank-of-anthos
- Release: `v0.6.11`, commit `710631448d24f612f43885d0ddd0991c90905990` (2026-09-18)
- License: Apache 2.0 (see `LICENSE`)

## What was imported

Copied unchanged: `src/` (services, Dockerfiles, tests, database init scripts), the root `pom.xml`,
the Maven wrapper (`mvnw`, `mvnw.cmd`, `.mvn/`), `.pylintrc` and `LICENSE`.

Left out on purpose. These are upstream deployment assets, which the capstone brief counts as
reference only; our deployment is our own Helm chart in `merlion-bank-infra`:

- the top-level `kubernetes-manifests/`, `iac/`, `extras/`, `docs/` and `.github/`
- every `k8s/` and `components/` folder, `skaffold*.yaml` and `cloudbuild.yaml`
- `src/ledgermonolith/`, a single-service variant we don't deploy

## Images built from it

| Service | Language | Built with |
|---|---|---|
| `frontend` | Python | `src/frontend/Dockerfile` |
| `userservice`, `contacts` | Python | `src/accounts/<service>/Dockerfile` |
| `loadgenerator` | Python (Locust) | `src/loadgenerator/Dockerfile` (staging only) |
| `ledgerwriter`, `balancereader`, `transactionhistory` | Java | Jib (Maven), `src/ledger/<service>/pom.xml` |
| `accounts-db`, `ledger-db` | PostgreSQL init scripts | `src/<area>/<db>/Dockerfile`; run once as a schema and demo-data job against RDS |

## Changes from upstream

Each change is made in its own reviewed PR and listed here.

| Change | Files | Reason |
|---|---|---|
| _(none yet)_ | | |
