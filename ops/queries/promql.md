# Saved metric queries (PromQL)

Run them in Grafana (**Explore**, data source **Prometheus**).

| Question | Query |
|---|---|
| Which ALB metrics does YACE deliver? | `count by (__name__) ({__name__=~"aws_applicationelb_.+"})` |
| Requests per minute at the ALB | `bank:alb_requests:count1m` |
| Failed requests per minute | `bank:alb_errors:count1m` |
| Availability, last hour (%) | `(1 - bank:error_ratio:1h) * 100` |
| p95 response time (s) | `bank:latency_p95:seconds` |
| Error budget left over 7 days (%) | `(1 - (sum_over_time(bank:alb_errors:count1m[7d]) / sum_over_time(bank:alb_requests:count1m[7d])) / 0.001) * 100` |
| Running pods per service | `kube_deployment_status_replicas_available{namespace="bank"}` |
| Restarts in the last hour | `sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace="bank"}[1h]))` |
| CPU per service (cores) | `sum by (container) (rate(container_cpu_usage_seconds_total{namespace="bank", container!=""}[5m]))` |
| Memory per service | `sum by (container) (container_memory_working_set_bytes{namespace="bank", container!=""})` |
| Memory against the limit | `sum by (container) (container_memory_working_set_bytes{namespace="bank", container!=""}) / sum by (container) (kube_pod_container_resource_limits{namespace="bank", resource="memory"})` |
| Node CPU used (%) | `100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Alerts firing now | `ALERTS{alertstate="firing"}` |
