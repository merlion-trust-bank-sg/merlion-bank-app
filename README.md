# merlion-bank-app

Bank of Anthos (upstream `v0.6.11`, see `UPSTREAM.md`) built into our own images
and deployed with **our own Helm chart** to EKS in us-east-1. Synthetic data only.

> As a 4-person team we doubled up on **DevSecOps**, the heaviest phase for Merlion
> Trust because auditability and credential separation are hard constraints. DO1
> owns the infrastructure foundations, DO2 owns data services and the delivery pipelines.

## From Jira ticket to production

```
SCRUM-42-short-desc --PR--> ci.yml (all required) --1 review + CODEOWNERS--> squash merge
                                                                                 |
cd.yml <-------------------------------------------------------------------------+
  build x9 ONCE -> Trivy image gate -> push ECR :<sha> (immutable) -> record digests
  dev        (gha-dev, auto)       helm upgrade -> wait -> smoke test
  staging    (gha-staging, auto)   same digests, loadgenerator on -> smoke test
  production (gha-prod)            PAUSED until a required reviewer approves
                                   (cannot approve your own run) -> deploy -> smoke
                                   -> deploy record to S3 Object Lock (365 days)
```

1. Branch from `main` as `SCRUM-<n>-<desc>`; commit as `SCRUM-<n>: type(scope): summary`.
2. Open a PR. `ci.yml` runs gitleaks, SCA, build + image scan for all 9 images, and a
   chart render. All must pass; 1 approval from someone other than the author; CODEOWNERS.
3. Merge. `cd.yml` builds each image **once** and promotes the **same digest**.
4. Production waits in the `production` GitHub Environment for a reviewer. Only that
   job can assume `gha-prod` (IAM trust pins `environment:production`).

Rollback: revert the PR; the pipeline redeploys the previous digests (still in ECR).

## When a security gate fails

1. Open the failed job. The table lists the package, installed version and fixed version.
2. **Fix first**: bump the dependency or base image and push to the same branch.
3. If there is no fix yet, add an entry to `security/.trivyignore` with a comment
   (reason, who accepted, Jira ticket) and an `exp:YYYY-MM-DD` expiry. CODEOWNERS
   requires DevSecOps approval. After the expiry the gate fails again.
4. Never add `--exit-code 0`, `continue-on-error` or `|| true` to a scanner.

Gates fail on HIGH/CRITICAL findings **that have a fix** (`--ignore-unfixed`): an
unfixable CVE cannot be acted on in a PR, and ECR scan-on-push still reports it.

## CI log hygiene

GitHub stores Actions logs outside us-east-1. The pipeline never handles customer data
or application logs: only code, synthetic demo data and scan results. Smoke tests print
HTTP status codes only. Secrets are never echoed (the JWT key is generated in the job
and written straight to Secrets Manager).

## Secrets

| Secret | Lives in | Reaches pods via |
|---|---|---|
| DB username/password | RDS-managed secret (Secrets Manager, KMS) | ExternalSecret -> `accounts-db-config` / `ledger-db-config` |
| DB host/port/name | `merlion/<env>/<db>-db-conn` | same ExternalSecret (merged) |
| JWT RS256 key pair | `merlion/<env>/jwt` | ExternalSecret -> `jwt-key` (mounted files) |
