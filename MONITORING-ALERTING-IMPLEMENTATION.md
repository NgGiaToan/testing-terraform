# Monitoring & Alerting — Implementation Status

Implements "Monitoring & Alerting — Hosted Lighthouse Customer Environments" in Terraform.

| Where | What |
| --- | --- |
| `modules/customer-monitoring` | Per customer account: priority SNS topics + KMS key, alarms, CloudWatch agent config, budget alerts, Grafana read-only role |
| `modules/alert-formatter` | Management account, per region: Slack formatter Lambda, quota job, Network Firewall / quota / pipeline alarms |
| `environment/shr-monitoring` | Applies `alert-formatter` (manual, admin-applied, like the other `shr-*` environments) |
| `environment/{dev-cus0001,stg-customer,prd-customer}` | Call `customer-monitoring` with `formatter_lambda_arn`, `management_account_id`, `engineering_alert_emails` |

## Alert catalogue

Priority and recipients are defined in one place per module: `alerts.tf` in
`customer-monitoring`, `main.tf` in `alert-formatter`. Alarm names are
`<customer>-<priority>-<alert-key>` (shared: `<priority>-<alert-key>`).

| Alert key | Pri | Notify | Trigger | Created when |
| --- | --- | --- | --- | --- |
| `status-check` | P1 | Ops | StatusCheckFailed, max 60 s, 3/3 ≥ 1 | `instance_id` |
| `https-canary` | P1 | Ops | SuccessPercent avg 60 s, 3/3 < 100, missing = breaching | `https_availability_canary_name` |
| `alb-healthy` | P1 | Ops | UnHealthyHostCount min 60 s, 3/3 ≥ 1 | `alb_arn_suffix` |
| `alb-5xx` | P2 | Ops | (target + ELB 5xx) ÷ requests > 5%, ≥ 50 req/min, 5/5 | `alb_arn_suffix` |
| `workflow-canary` | P2 | Ops | SuccessPercent avg 300 s, 2/2 < 100, missing = breaching | `synthetics_canary_name` |
| `ebs-status` | P2 | Ops | StatusCheckFailed_AttachedEBS, max 60 s, 3/3 ≥ 1 | `instance_id` |
| `cpu-warning` / `cpu-critical` | P3 / P2 | Ops | avg 60 s; 15/15 > 70, 10/10 > 90 | `instance_id` |
| `memory-warning` / `memory-critical` | P3 / P2 | Ops | avg 60 s; 15/15 > 70, 10/10 > 85 | `instance_id` |
| `disk-warning` / `disk-critical` | P3 / P2 | Ops | avg 300 s; 3/3 > 80, > 90; one per mount point | `instance_id` |
| `alb-latency` | P2 | Ops | p95 60 s, 10/10 > 0.3 s | `alb_arn_suffix` |
| `alb-request-rate` | P3 | Ops | Sum 60 s, 10/10 above anomaly band (3) | `alb_arn_suffix` |
| `network-egress` | P3 | Ops | NetworkOut Sum 300 s, 6/6 above band (3) | `instance_id` |
| `agent-heartbeat` | P2 | Eng | mem_used_percent SampleCount 300 s, 2/2 < 1, missing = breaching | `instance_id` |
| `vpn-healthy` | P1 | Ops | NLB UnHealthyHostCount **max** 60 s, 3/3 ≥ 1 | `nlb_arn_suffix` |
| `vpn-connections` | P2 | Ops | ActiveFlowCount avg 300 s, 3/3 below band (3) | `nlb_arn_suffix` |
| `waf-blocked` | P3 | Ops | BlockedRequests Sum 300 s, 2/2 above band (3) | `waf_web_acl_name` |
| `cert-warning` / `cert-critical` | P2 / P1 | Ops | DaysToExpiry < 30 / < 7, missing = breaching | `acm_certificate_arn` |
| `backup-25h` | P1 | Eng | SnapshotSucceeded Sum 1 h, 25/25 < 1, missing = breaching | `backup_monitoring_enabled` |
| `sns-failures` | P2 | Eng | NumberOfNotificationsFailed ≥ 1 per priority topic → **email** | always |
| `firewall-drops` | P3 | Ops + Eng | DroppedPackets summed over AZ × engine, 2/2 above band (3) | `network_firewall_name` |
| `quota-80` / `quota-95` | P3 / P2 | Ops + Eng | QuotaUsagePercent > 80 / > 95 per quota | always |
| `lambda-errors`, `lambda-throttles` | P2 | Eng | Sum ≥ 1 → **email** | always |

Also created: `quota-job-errors` (P2, email), an extra alarm on the quota publisher Lambda, which
the spec mentions but does not list.

## Slack

The formatter Lambda (`modules/alert-formatter/lambda_src/slack_formatter.py`) posts through
Slack Incoming Webhooks. The secret (`slack_webhook_secret_arn`) holds one URL, or JSON with a
URL per team (`Operations`, `Engineering`). A message shows priority, customer, service, alert, the trigger in
words, state and a link to the Environment Overview dashboard, with a colour bar per priority and
green on recovery. Setup steps are in `modules/alert-formatter/README.md`.

## Deviations and open items

- **Subscription direction.** The spec has the topic policy let the management account subscribe.
  Here the customer account (topic owner) subscribes the Lambda, and the Lambda's resource policy
  allows the customer account. The topic policy still grants the management account subscribe
  rights, so either direction works.
- **`notify` is an extra field** in the alarm description JSON (the spec lists six fields). The
  Lambda needs it to choose between the Operations and Engineering channels.
- **Channel names, Slack token, emails, Grafana account/external ID** are placeholders or null
  until real values exist.
- **`backup_monitoring_enabled` defaults to false.** The spec's `Lighthouse/Backup`
  `SnapshotSucceeded` metric has no publisher in this repo yet.
- **Cost monitoring** ("visibility" and "budget alerts") is still "to be defined" in the spec.
  Budget notifications keep the existing Customer-tag filter and are routed 80% / forecast → P3,
  100% → P2.
- **Grafana dashboards** are importable JSON in `modules/customer-monitoring/grafana-dashboards`
  (six dashboards, thresholds drawn on panels, the Customer dropdown selects the data source).
  They are not auto-provisioned and have not been imported into a live Grafana. The
  management-account read-only role is created by `alert-formatter` when `grafana_account_id`
  and `grafana_external_id` are set. Disk I/O panels have no alarm; the per-volume `AWS/EBS`
  panels are an addition for non-Nitro instances. "Active alerts" on Environment Overview and
  the HTTPS canary failure reason are not metrics, so they are not panels.
- **Disk dimensions** (`device`, `fstype`) default to guesses; confirm against the real agent output.
- **`monitored_instance_ids` is now `instance_id`** (one Lighthouse instance per customer; alarm
  names must be unique). The old two-topic design (full-detail / status-only) and the per-customer
  Slack Lambda are removed.
- **Not tested against AWS.** `terraform validate` passes for both modules and every environment
  that calls them; nothing has been planned or applied, and the Lambda code has not been run.
  Test with `aws cloudwatch set-alarm-state` after deploying.
