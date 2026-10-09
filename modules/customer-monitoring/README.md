# customer-monitoring

Per-customer monitoring and alerting for a hosted Lighthouse environment, implementing
"Monitoring & Alerting — Hosted Lighthouse Customer Environments". Call it once per customer
account. Management-account pieces (Slack formatter Lambda, Network Firewall and quota
alarms) live in [`../alert-formatter`](../alert-formatter/README.md); see
[`MONITORING-ALERTING-IMPLEMENTATION.md`](../../MONITORING-ALERTING-IMPLEMENTATION.md) for
the alert-by-alert status.

## How an alert flows

```text
CloudWatch alarm ──► SNS topic (one per priority, this account, KMS-encrypted)
                       └─► formatter Lambda (management account, cross-account) ──► Slack
```

- Alarm name: `<customer>-<priority>-<alert-key>`, e.g. `acme-P1-https-canary`.
- Alarm description: JSON (`priority`, `customer`, `alert_type`, `service`, `condition`,
  `dashboard_url`, `notify`) written by Terraform from the same variables as the alarm. The
  Lambda reads it to build the Slack message; `notify` (`Operations` / `Engineering`) picks
  the channel.
- `alarm_actions` and `ok_actions` both publish to `<environment>-monitoring-alerts-p1/p2/p3`.
- Everything about an alert — priority, audience, wording — is defined once in
  [`alerts.tf`](alerts.tf). To change a priority or a recipient, change it there.

## Usage

```hcl
module "monitoring" {
  source = "../../modules/customer-monitoring"

  customer_code = "acme"
  environment   = "prod-acme"
  region        = "us-east-1"

  # Slack delivery (outputs of modules/alert-formatter)
  formatter_lambda_arn  = "arn:aws:lambda:us-east-1:<mgmt>:function:lighthouse-alerting-formatter"
  management_account_id = "<mgmt>"
  dashboard_url         = "https://grafana.example.com/d/overview?var-customer=acme"
  engineering_alert_emails = ["eng-oncall@example.com"]

  # What to watch — each group is skipped while its input is null
  instance_id                    = "i-0abc"
  existing_ec2_role_name         = "ec2_role"
  alb_arn_suffix                 = aws_lb.app.arn_suffix
  target_group_arn_suffix        = aws_lb_target_group.app.arn_suffix
  nlb_arn_suffix                 = aws_lb.vpn.arn_suffix
  nlb_target_group_arn_suffix    = aws_lb_target_group.openvpn.arn_suffix
  waf_web_acl_name               = aws_wafv2_web_acl.app.name
  acm_certificate_arn            = aws_acm_certificate.app.arn
  https_availability_canary_name = module.canaries.https_availability_canary_name
  synthetics_canary_name         = module.canaries.workflow_canary_name
  backup_monitoring_enabled      = true
}
```

With only the three identity variables the module still creates the topics, the KMS key, the
pipeline topic, the budget and the cost-anomaly monitor.

## Things to know

- **The pipeline topic is not wired to the Lambda.** The `sns-failures` alarms watch the
  priority topics' delivery, so they notify `<environment>-monitoring-alerts-pipeline`, which
  delivers by email (`engineering_alert_emails`). With no emails it has no subscribers, so
  set them.
- **Topics need a customer-managed KMS key.** The AWS managed key makes the alarm action
  fail. The module creates one with a policy allowing `cloudwatch.amazonaws.com`.
- **Detailed monitoring** must be enabled on the instance for the one-minute CPU alarms.
- **`mount_points`** must match the `path`/`device`/`fstype` the agent really reports — check
  `aws cloudwatch list-metrics --namespace CWAgent --metric-name disk_used_percent`. The
  default device (`nvme0n1p1`) and filesystem (`xfs`) are guesses. One warning and one
  critical alarm is created per entry.
- **`backup_monitoring_enabled`** is off by default. The alarm reads the custom
  `Lighthouse/Backup` `SnapshotSucceeded` metric (dimension `Customer`) which the daily AMI
  snapshot job must publish; missing data counts as breaching, so turning it on first raises
  a P1 immediately.
- **Anomaly-detection alarms** (request rate, network egress, VPN connections, WAF) need
  about two weeks of history; expect noise for a new customer.
- **Cost:** budget alerts are routed by priority (80% actual or forecast over 100% → P3,
  100% actual → P2) and the anomaly monitor goes to P3. The spec's Cost Monitoring sections
  are still "to be defined", so the budget filter (Customer tag) is unchanged. Activate the
  Customer cost allocation tag in Billing first.
- **Grafana:** set `grafana_account_id` and `grafana_external_id` to create the read-only
  role (CloudWatch read only, trust limited to that account with the external ID); enter the
  `grafana_role_arn` output as the data source's `Assume Role ARN`. Dashboards are importable
  JSON in `grafana-dashboards/` (Grafana → Dashboards → Import; pick the customer's data
  source in the **Customer** dropdown): `env-overview`, `infrastructure`, `remote-access`,
  `application`, `web-protection` and `platform`. Alarm thresholds are drawn on the panels.
  The Infrastructure disk read/write panels (bytes and operations) are dashboard only, with no
  alarm: the first four use the per-instance `AWS/EC2` metrics (Nitro instances only), the
  last four use per-volume `AWS/EBS` metrics, which also work on older instances. The
  firewall, quota and Lambda panels use a second data source for the management account
  (`mgmt_datasource` dropdown); see `modules/alert-formatter` (`grafana_role_arn`).
