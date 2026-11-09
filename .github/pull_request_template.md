## What changed

## Why

## Jira
SCRUM-<n>: https://<your-site>.atlassian.net/browse/SCRUM-<n>

## Evidence
- [ ] `ci.yml` green: gitleaks, SCA, build + image scan
- [ ] Any new `security/.trivyignore` entry has a reason, ticket and expiry

## Constraint impact
- Region (images stay in ECR in us-east-1):
- Audit / retention:
- Credentials (roles, trust, secrets):

## Definition of done
- [ ] Branch is `SCRUM-<n>-*`, commit messages `SCRUM-<n>: type(scope): summary`
- [ ] Reviewer is not the author
- [ ] No secrets in code, images or logs
- [ ] Docs / ADR / diagram updated if the design changed
