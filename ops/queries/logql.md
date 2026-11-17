# Saved log queries (LogQL)

All six services log JSON to stdout: `{"timestamp": "...", "message": "<function> | <text>", "severity": "INFO"}`.
Grafana Alloy sends every pod's logs to Loki with the labels `namespace`, `app`, `pod` and `container`.
Logs are kept 365 days in S3 in `us-east-1`.

Run them in Grafana (**Explore**, data source **Loki**) or with `logcli`:

```bash
kubectl -n monitoring port-forward svc/loki 3100:3100 &
export LOKI_ADDR=http://localhost:3100
logcli query --since=1h '{namespace="bank", app="frontend"}'
```

## Is every service logging? (APP-13 check)

```logql
sum by (app) (count_over_time({namespace="bank"}[15m]))
```

Expect seven rows in staging: `frontend`, `userservice`, `contacts`, `ledgerwriter`, `balancereader`,
`transactionhistory`, `loadgenerator`. Six in prod.

## One service

```logql
{namespace="bank", app="ledgerwriter"}
```

## Errors, all services

```logql
{namespace="bank"} | json | severity=~"ERROR|CRITICAL|FATAL"
```

## Errors per service, per 5 minutes (graph)

```logql
sum by (app) (count_over_time({namespace="bank"} | json | severity=~"ERROR|CRITICAL|FATAL" [5m]))
```

## Failed logins

```logql
{namespace="bank", app="frontend"} |= "Error logging in"
```

## Failed payments and deposits

```logql
{namespace="bank", app="frontend"} |~ "Error submitting (payment|deposit)"
```

## Ledger write failures

```logql
{namespace="bank", app="ledgerwriter"} |~ "Transaction submission failed|Failed to submit transaction"
```

## Database unreachable

```logql
{namespace="bank", app=~"balancereader|transactionhistory"} |~ "Could not (reach|contact) ledger database"
```

```logql
{namespace="bank"} |~ "(?i)(connection refused|could not connect|SQLSTATE|OperationalError|JDBCConnectionException)"
```

## Everything one pod said before it restarted

```logql
{namespace="bank", pod="<pod name>"}
```

## Monitoring stack's own logs

```logql
{namespace="monitoring"} |~ "(?i)level=(error|warn)"
```
