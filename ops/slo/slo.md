# Service level objectives: Merlion Trust Bank

Owner: SRE. Rules that implement this page: `merlion-bank-infra/deploy/helm/observability/rules/bank-slo.rules.yaml`.

## What the customer does

A customer logs in, checks a balance, reads transaction history and makes a payment. Every one of
those is an HTTPS request to the load balancer (ALB) in front of `frontend`. So both SLIs are measured
**at the ALB**: it sees what the customer sees, including the case where no pod is healthy and the
ALB itself answers 503.

## SLIs and SLOs

| | SLI (how it is measured) | SLO (target) | Window |
|---|---|---|---|
| **Availability** | Requests answered without a 5xx, divided by all requests. `1 - (HTTPCode_Target_5XX_Count + HTTPCode_ELB_5XX_Count) / RequestCount` | **99.9%** | 30 days |
| **Latency** | 95th percentile of `TargetResponseTime` | **under 500 ms** | 5-minute windows; at least 99% of them under target in 30 days |

Source: the ALB's CloudWatch metrics, copied into Prometheus every minute by YACE (ADR-003).
4xx responses count as good: a wrong password is the customer's error, not ours.

## Why these targets

- **99.9% availability.** A transaction-enquiry portal is how customers see their money; MAS expects
  critical systems to be highly available, and 99.9% is the highest target our design can honestly
  meet: two AZs, 2+ `frontend` replicas, Multi-AZ RDS in prod, but single replicas of the five backend
  services and a single region. 99.99% would need multi-replica backends and tested failover.
- **p95 under 500 ms.** A balance or history page that takes longer than half a second feels broken
  on mobile. `frontend` waits at most 4 s for a backend (`BACKEND_TIMEOUT`), so a slow backend shows
  up here before it turns into errors. p95 and not the average: the average hides the slow tail.

## Error budget

| | |
|---|---|
| Allowed failures | 0.1% of requests in 30 days |
| As downtime | 43 minutes 12 seconds of full outage in 30 days (30 × 24 × 60 × 0.001) |
| At 100,000 requests a day | 3,000 failed requests in 30 days |

Policy:

- **Budget left:** deploy normally (staging promotion PR, then prod promotion PR).
- **More than half spent in a week:** the next prod promotion needs the SRE's approval.
- **Budget spent:** only fixes are promoted to prod until the 30-day number is back above 99.9%.

## Alerts tied to the SLOs

| Alert | Fires when | Means | Severity |
|---|---|---|---|
| `BankAvailabilityFastBurn` | Error ratio above 1.44% over 1 h and over 5 min | Budget burning 14.4× too fast: 2% of the month's budget gone in an hour | critical |
| `BankAvailabilitySlowBurn` | Error ratio above 0.6% over 6 h and over 30 min | Burning 6× too fast: 5% of the budget in 6 hours | warning |
| `BankLatencyP95High` | p95 above 500 ms for 10 min | Latency SLO at risk | warning |
| `BankServiceDown` | A bank Deployment has 0 available pods for 2 min | Key failure mode; works without traffic | critical |
| `BankPodCrashLooping` | More than 3 restarts in 15 min | Early warning | warning |
| `BankSliMissing` | No ALB metrics for 15 min | The SLO alerts are blind | warning |

All go to the team's Telegram group through Alertmanager. Runbook: `ops/runbooks/bank-service-down.md`.

## Limits we know about

- ALB metrics reach Prometheus 2 to 3 minutes late (CloudWatch delay plus a one-minute scrape).
  `BankServiceDown` comes from Kubernetes directly and fires sooner.
- The staging loadgenerator calls `frontend` inside the cluster, not through the ALB, so it doesn't
  feed the SLIs. With no outside traffic the SLIs show "no data", which is correct: no requests, no
  ratio. `ops/demo/traffic.sh` sends outside traffic.
- Prometheus keeps 15 days of metrics, so the dashboard shows the budget over 7 days. The 30-day
  number is a manual query at month end until long-term metric storage exists.
