# Monitoring & Alerting — Implementation Status

Implements "Monitoring & Alerting — Hosted Lighthouse Customer Environments" in Terraform.

| Where | What |
| --- | --- |
| `modules/customer-monitoring` | Per customer account: alarms (they publish to the management account's topics),  CloudWatch agent config, Grafana read-only role |
| `modules/alert-delivery` | Management account, **per environment and region**: Slack alert delivery Lambda, webhook secret, the priority topics the environment's alarms publish to (one policy statement for any account), Network Firewall / quota / pipeline alarms |
| `environment/shr-monitoring` | Applies `alert-delivery` for one environment in one region (manual, admin-applied, like the other `shr-*` environments); one workspace per deployment, `<environment>-<region>` (the `workspace_guard` check is commented out for now) |
| `environment/grafana-datasources` | Grafana reads CloudWatch (the first Grafana step), applied through the Grafana API (not AWS): every customer is in the same AWS account as the monitoring, so one CloudWatch data source reads them all (one data source per customer account is the alternative). Not validated |
| `environment/grafana-alerting` | **Switched off for now (commented out).** Grafana watches the alert pipeline, applied through the Grafana API: rules that alert to Slack when the pipeline fails, and the heartbeat to AWS. Needs `grafana-datasources` applied first. Not validated |
| `environment/{dev-cus0001,stg-customer,prd-customer}` | Call `customer-monitoring` with `management_account_id` |

## Alert catalogue

Priority and recipients are defined in one place per module: `alerts.tf` in
`customer-monitoring`, `main.tf` in `alert-delivery`. Alarm names are
`<customer>-<priority>-<alert environment>-<alert-key>` (shared, management account:
`shared-<priority>-<environment>-<alert-key>`). The alert environment is dev, stg, prd or the full
environment name.

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
| `sns-failures` | P2 | Eng | NumberOfNotificationsFailed ≥ 1 on each alert topic (management account) → pipeline topic (delivers to the alert delivery Lambda) | always |
| `grafana-heartbeat` (**the alarm stays off until `grafana_heartbeat_alarm_enabled`**) | P2 | Eng | NumberOfMessagesPublished of the heartbeat topic < 1 for 15 minutes (3 x 5 min), missing = breaching | `grafana_heartbeat_alarm_enabled` |
| `firewall-drops` | P3 | Ops + Eng | DroppedPackets summed over AZ × engine, 2/2 above band (3) | `network_firewall_name` |
| `quota-80` / `quota-95` | P3 / P2 | Ops + Eng | `AWS/Usage` `ResourceCount` / `SERVICE_QUOTA()` × 100 > 80 / > 95 per quota (metric math, no Lambda) | always |
| `lambda-errors`, `lambda-throttles` | P2 | Eng | Sum ≥ 1 → pipeline topic (delivers to the alert delivery Lambda; **cannot reach Slack while that Lambda is down**) | always |

The quota publisher Lambda and its `quota-job-errors` alarm were removed: the quota alarms read the usage
metric that AWS publishes itself.

## Slack

The alert delivery Lambda (`modules/alert-delivery/lambda_src/slack_formatter.py`) posts through
Slack Incoming Webhooks. The secret (`slack_webhook_secret_arn`) is JSON with one webhook URL
per team (`Operations`, `Engineering`), each posting to its own channel. A message shows priority, customer, service, alert, the trigger in
words, state and a link to the Environment Overview dashboard, with a colour bar per priority and
green on recovery. Setup steps are in `modules/alert-delivery/README.md`.

## Deviations and open items

- **Topics live in the management account.** The spec has each topic in the same account as the
  alarm, subscribed cross-account to the Lambda. With hundreds of customer accounts that does not
  scale (the Lambda's resource policy is limited to 20 KB, one statement per account). Instead the
  alarms of every account publish to the management account's topics, whose policy takes
  alarms from any account with one statement, limited by alarm name. Not verified against real
  alarms yet; see the alert-delivery README.
- **One deployment per environment and region.** Each environment (dev, stg, prd, or a full name)
  has its own alert delivery Lambda, role, webhook secret and alert topics, so its alerts can go to its
  own Slack channels. A customer environment picks the topics of its own environment from its name.
  This is wiring by name: the topic policy takes alarms from any account and does not check the
  environment. A customer environment with no matching deployment fails silently. The shared
  regional parts (the Grafana heartbeat and read-only role) must be turned on in one
  deployment per region; nothing checks this across states.
- **Alarm names carry the environment** (`acme-P1-prd-https-canary`), unlike the spec's
  `<customer>-<priority>-<alert-key>`, so that two environments of a customer in one account and
  region cannot overwrite each other's alarms.
- **Two-way watch with Grafana.** Customer alerts stay on CloudWatch, SNS and the Lambda. Grafana
  alerts to Slack when the Lambdas or topics fail, and the pipeline alerts when Grafana's heartbeat
  stops (an always-firing Grafana rule publishes to an SNS topic every 5 minutes). Neither side can
  report its own failure, and if both fail at once nobody is told. Grafana Cloud takes no
  provisioning files, so `environment/grafana-alerting` is Terraform against its API; nothing there
  has been validated or run.
- **The alert topics are open to any AWS account**, limited only by the alarm name (the P1 topic
  takes `*-P1-*`), which is a naming rule and not a security boundary. Anyone who knows a topic ARN
  can send alerts to Slack, and a private webhook URL does not prevent it. Close them by listing
  the allowed accounts in the policy if that becomes a problem.
- **The alert topics are encrypted with a customer-managed KMS key** (`modules/alert-delivery/kms.tf`).
  The spec says a topic may only be encrypted with a customer-managed KMS key that lets CloudWatch
  use it. The key policy names the CloudWatch service for alarms of any account in the region, so
  adding a customer needs no key change. Not verified: the AWS docs show this for one account's
  alarms, so test with a real alarm in a customer account after applying.
- **`notify` is an extra field** in the alarm description JSON (the spec lists six fields). The
  Lambda needs it to choose between the Operations and Engineering channels.
- **Email alerts are removed.** The pipeline topic (delivery failures, Lambda errors and
  throttles) delivers to the same alert delivery Lambda, so those alarms reach Slack, except
  while that Lambda is down (`lambda-errors`, `lambda-throttles`). A path independent of the Lambda
  is still to be added.
- **Webhook secret and Grafana account ID** are placeholders or null
  until real values exist.
- **`backup_monitoring_enabled` defaults to false.** The spec's `Lighthouse/Backup`
  `SnapshotSucceeded` metric has no publisher in this repo yet.
- **Cost monitoring** is kept centrally in the management account: `modules/cost-monitoring` (called from
  `environment/shr-monitoring`, `cost_customers`) makes one budget and one cost anomaly monitor per customer,
  filtered on the `Instance` tag, which is unique per customer. Alerts
  go to the alert topics: 80% / forecast → P3, 100% → P2, anomaly → P3. Written, not applied; the tag has to be
  activated in Billing first. See IMPLEMENTATION-GRAFANA-COST.md, part B.
- **Grafana dashboards** are importable JSON, managed in the `graham-infrastructure` repository;
  `modules/customer-monitoring/grafana-dashboards` holds the hand-off copy of the first six (see its
  README), and a new dashboard is added to `graham-infrastructure`. Six dashboards, thresholds drawn
  on panels. The customer is picked by tag (`Customer`, `Environment`) on the one data source; the copies in this
  repository still carry the older `account` variable and `accountId` on every customer query, which
  has to be changed (see IMPLEMENTATION-GRAFANA-COST.md, A9). They are not provisioned from this
  repository and have not been imported into a live Grafana. The
  management-account read access is a federation role in its own stack, `environment/shr-grafana-federation`
  (the IAM user and the role route, `grafana_account_id`, are commented out). Every customer is in the same
  account, so no cross-account setup is needed; nothing of it has been applied. Disk I/O panels have no alarm; the per-volume `AWS/EBS`
  panels are an addition for non-Nitro instances. "Active alerts" on Environment Overview and
  the HTTPS canary failure reason are not metrics, so they are not panels.
- **Disk dimensions** (`device`, `fstype`) default to guesses; confirm against the real agent output.
- **`monitored_instance_ids` is now `instance_id`** (one Lighthouse instance per customer; alarm
  names must be unique). The old two-topic design (full-detail / status-only) and the per-customer
  Slack Lambda are removed.
- **Not tested against AWS.** `terraform validate` passes for both modules and every environment
  that calls them; nothing has been planned or applied, and the Lambda code has not been run.
  Test with `aws cloudwatch set-alarm-state` after deploying.
