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
| Removed the `src/ledgermonolith` module from the root Maven project | `pom.xml` | `ledgermonolith` wasn't imported (we don't deploy it), and Maven refuses to build a project with a missing module |
| Python base image `python:3.14.7-slim` → `python:3.14.10-slim` (pinned digest) | `src/frontend`, `src/accounts/userservice`, `src/accounts/contacts`, `src/loadgenerator` Dockerfiles | CI image scan: critical in Debian's `perl-base` (CVE-2026-13221) and other fixed OS packages |
| Postgres base image: newer `postgres:16.15-alpine` build (pinned digest, gosu 1.19) | `src/accounts/accounts-db`, `src/ledger/ledger-db` Dockerfiles | CI image scan: critical in the Go standard library inside `gosu` (CVE-2025-68121) |
| Java base image `eclipse-temurin:17.0.4.1_1-jre-alpine` (2022) → `17.0.21_9-jre-alpine` | Jib `<from>` in the 3 `src/ledger/*/pom.xml` | CI image scan: outdated JRE and Alpine packages |
| `certifi` 2026.7.22 → 2026.10.23 | `uv.lock` in the 4 Python services | CI scans: critical GHSA-6q48-6c7w-9gw2 (CA bundle included compromised emSign roots) |
| `brotli` 1.2.0 → 1.2.1 | `src/loadgenerator/uv.lock` | CI scans: critical CVE-2026-111497 (out-of-bounds write) |
| Netty pinned to 4.1.137.Final (`netty.version`) | the 3 `src/ledger/*/pom.xml` | CI scans: critical CVE-2026-75595 in `netty-handler` (SNI routing bypass); same 4.1 line as Spring Boot 3.5's default |

Not changed, with a documented exception in `security/.trivyignore`: `spring-webmvc` 6.2.19 (CVE-2026-47884). The only fix is Spring 7 / Spring Boot 4; the vulnerable `XsltView` isn't used by any service.
