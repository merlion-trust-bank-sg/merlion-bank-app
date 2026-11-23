# Runbook: a bank service is down or the bank is returning errors

| | |
|---|---|
| Alerts | `BankServiceDown`, `BankAvailabilityFastBurn`, `BankAvailabilitySlowBurn`, `BankPodCrashLooping`, `BankLatencyP95High`, `BankDatabaseUnreachable`, `BankSliMissing` (step 7) |
| Customer impact | Login, balance, history or payments fail or are slow |
| SLO at risk | 99.9% availability (43 minutes of outage allowed in 30 days), p95 under 500 ms (`ops/slo/slo.md`) |
| Owner | SRE on call. Escalation in step 9. |

Rule for the whole runbook: **look with kubectl, change through Git.** People are read-only in prod;
every change there is a reviewed PR that Argo CD deploys (HC-2). Argo CD's self-heal undoes changes
made by hand within minutes, so they don't stick anyway. The one exception in prod is the named
break-glass holder (yqyeoh, DevSecOps), who may restart or restore in an emergency; every such action
is in the EKS audit log. Staging allows `kubectl` changes for tests and the alert demo; record any you
make.

## 1. Detection

- Telegram message from Alertmanager in the team alert group. It names the alert and, for
  `BankServiceDown`, the deployment. Each alert's `runbook_url` (Grafana → Alerting → Alert rules) links to this page.
- Or: someone reports the site is down. Check the dashboard first (step 2).

Acknowledge in the group ("I have it") so two people don't work on it separately. Note the time.

## 2. How bad is it? (2 minutes)

Open Grafana and log in (team: `admin`; assessors and other viewers: `viewer`), dashboard
**Merlion Trust Bank: is the system healthy?**

| Environment | Grafana |
|---|---|
| prod | https://grafana.merlion.sctp-sandbox.com (once merlion-bank-infra #65 is applied) |
| staging | https://grafana.merlion-staging.sctp-sandbox.com |

| Top row shows | Meaning | Go to |
|---|---|---|
| Services down ≥ 1 | A service has no pods | Step 3 |
| Services down = 0, failed requests rising | Pods run but answer 5xx | Step 4 |
| Only p95 red | Slow, not failing | Step 5 |
| Everything "no data" | Monitoring problem, not the bank | Step 7 |

Confirm from outside:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://merlion.sctp-sandbox.com/ready
curl -s -o /dev/null -w '%{http_code}\n' https://merlion-staging.sctp-sandbox.com/ready   # staging
```

200 = up; 503 = the load balancer has no healthy `frontend` pod; 502 = `frontend` closed the connection
or sent a bad response (often a pod restarting); 504 = `frontend` didn't answer in time (a slow backend
or database, see step 5); 500 = `frontend` itself failed.

## 3. A service has no pods

Anyone can run `aws eks update-kubeconfig`; what you can then do depends on the access in
`merlion-bank-infra/envs/prod/eks.tf`:

| Who | Prod access |
|---|---|
| SRE (paulyapsl), SA (kealeee) | Viewer: `get`, `describe`, `logs` |
| Break-glass holder (yqyeoh, DevSecOps) | Cluster admin: restarts and restores in an emergency, recorded |
| Prod pipeline role | Cluster admin: every normal change |

```bash
aws eks update-kubeconfig --name g4-merlion-prod --region us-east-1
kubectl -n bank get deploy,pods -o wide
kubectl -n bank describe pod <pod>          # read Events at the bottom
kubectl -n bank logs <pod> --previous       # what it said before it died
kubectl -n argocd get applications          # is bank-of-anthos Synced and Healthy?
```

In prod the SRE has read-only (viewer) access: `get`, `describe` and `logs` work; `port-forward`,
`scale` and `rollout restart` don't. Use Grafana's address instead of port-forwards.

| What you see | Cause | Mitigation |
|---|---|---|
| Deployment shows `0/0` | Its replica count was set to 0 (a values change, or a test in staging) | Prod: find the change in `deploy/` on `main` and revert it by PR. Staging: `kubectl -n bank scale deploy/<name> --replicas=2` (every service runs 2 since merlion-bank-infra #62); record it. |
| `ImagePullBackOff` | Digest not in ECR (account cleanup, or a bad promotion) | Roll back (step 6), or re-run `cd` in `merlion-bank-app` to republish |
| `ImagePullBackOff` with `403`, `no basic auth credentials` or `AccessDenied` in the pod events, often with CoreDNS down and Argo CD showing `Unknown` | The training account's nightly cleanup removed the policies from our IAM roles (node role, add-on roles, pipeline roles). Seen on 18 Nov. | Escalate to the break-glass holder. Staging: `scripts/restore-iam.sh staging` (account admin). Prod: `scripts/restore-iam.sh prod`, by the break-glass holder only; it writes a record to the audit bucket. Then restart Argo CD's controller and check that `kubectl -n kube-system get endpoints kube-dns` lists addresses. |
| `CrashLoopBackOff`, started after a deploy | Bad release | Roll back (step 6) |
| `CrashLoopBackOff`, logs show database or secret errors | Database or credentials | Step 4 |
| `Pending`, event `Insufficient cpu/memory` or `Too many pods` | Nodes full | `kubectl get nodes`; raise the node group's size in `envs/<env>/eks.tf` by PR |
| `OOMKilled` | Memory limit too low | Raise `resources.limits.memory` for that service in `deploy/helm/bank-of-anthos/values.yaml` by PR |
| Deployment shows `1/2` for more than a few minutes | One of the two replicas is gone; the service still works on the other. `BankServiceDown` doesn't fire (it needs 0) | Same diagnosis as above for the missing pod (`describe`, `logs --previous`). Not customer-facing yet, but the service has no spare |

## 4. Pods run but requests fail

Find which service is failing. In Grafana **Explore** (Loki), from `ops/queries/logql.md`:

```logql
sum by (app) (count_over_time({namespace="bank"} | json | severity=~"ERROR|CRITICAL|FATAL" [5m]))
{namespace="bank"} |~ "(?i)(connection refused|could not connect|SQLSTATE|OperationalError|JDBCConnectionException)"
```

(Explore needs the `admin` login; the `viewer` login sees the dashboard's log panel only.)

**Database.** Errors from `userservice` or `contacts` point at `accounts-db`; from `ledgerwriter`,
`balancereader` or `transactionhistory` at `ledger-db`.

```bash
aws rds describe-db-instances --region us-east-1 \
  --query 'DBInstances[?starts_with(DBInstanceIdentifier,`g4-merlion-prod`)].[DBInstanceIdentifier,DBInstanceStatus,MultiAZ]' --output table
aws rds describe-events --region us-east-1 --duration 60 --source-type db-instance
```

- Status `failing-over`, `rebooting` or `modifying`: Multi-AZ failover takes 1 to 2 minutes. Wait and
  watch the error panel fall. If pods don't reconnect within 5 minutes, they need a restart: in prod
  ask the break-glass holder (yqyeoh, DevSecOps) to run `kubectl -n bank rollout restart deploy/<service>`,
  and record it in the incident notes.
- Status `stopped` or instance missing: escalate to DevSecOps; the fix is a pipeline apply.

**Credentials.** Logs show `password authentication failed`, or JWT errors.

```bash
kubectl -n bank get externalsecrets        # all should be SecretSynced / True
kubectl -n bank describe externalsecret ledger-db
```

RDS rotates the master password; External Secrets picks it up within an hour, and pods only read it
at start. `SecretSyncedError` = the External Secrets role or the secret is broken (escalate).
Synced but pods still fail = the pods need a restart (as above).

## 5. Slow, not failing

- **Running pods per service** and **CPU per service** panels: is `frontend` at its HPA maximum
  (`kubectl -n bank get hpa`)? If so, raise `maxReplicas` by PR.
- A Java service near its memory limit pauses for garbage collection: check **Memory per service**.
- RDS: `CPUUtilization` and `DatabaseConnections` in the RDS console (read-only).
- Slow right after a deploy: roll back (step 6).

## 6. Roll back a release (the standard mitigation)

Follow the team's rollback runbook:
[merlion-bank-infra/docs/runbooks/rollback.md](https://github.com/merlion-trust-bank-sg/merlion-bank-infra/blob/main/docs/runbooks/rollback.md).

In short: revert the last merged `promote/<env>` PR, a teammate approves, Argo CD redeploys the
previous images. Say "incident" in the Telegram group so the approval is quick. The revert PR, its
approval and the Argo CD sync are the audit trail of the mitigation. Don't use `kubectl rollout undo`
or Argo CD's rollback button; self-heal undoes them.

## 7. Monitoring itself is down

```bash
kubectl -n monitoring get pods
kubectl -n argocd get applications
```

No Watchdog heartbeat in Telegram for more than 12 hours means Prometheus or Alertmanager is down.
The bank may be fine; check it with the `curl` in step 2.

If YACE, External Secrets and Loki all fail at the same time, and `BankSliMissing` fires, suspect the
nightly IAM cleanup first: see the `403` row in step 3.

## 8. Confirm recovery

- Services down = 0; failed requests back to 0; `curl` returns 200.
- Telegram shows **RESOLVED** for the alert (within about 5 minutes).
- Log in to the bank as `testuser` and open the transaction history.

## 9. Escalation

| When | Who | How |
|---|---|---|
| Not mitigated in 15 minutes, or you need a prod change or a pod restart in prod | Break-glass holder: yqyeoh, DevSecOps (pipeline, EKS, RDS) | Telegram group, then phone |
| Not mitigated in 30 minutes, or the audit trail or data residency may be affected | Solutions Architect: kealeee | Telegram group, then phone |
| Customer data may be exposed or lost, or outage over 1 hour | Lecturer (stands in for the bank's incident manager and the MAS notification decision) | Email |

## 10. Afterwards (within 2 working days)

Jira issue with: timeline (alert time, acknowledge, mitigation, recovery), error budget spent
(failed requests ÷ allowed, from the dashboard), root cause, what we change so it doesn't recur.
Blameless: what in the system allowed it, not who did it.
