# customer-monitoring

Per-customer monitoring and alerting for a hosted Lighthouse environment, implementing
"Monitoring & Alerting — Hosted Lighthouse Customer Environments". Call it once per customer
account. Management-account pieces (Slack alert delivery Lambda, Network Firewall and quota
alarms) live in [`../alert-delivery`](../alert-delivery/README.md); see
[`MONITORING-ALERTING-IMPLEMENTATION.md`](../../MONITORING-ALERTING-IMPLEMENTATION.md) for
the alert-by-alert status.

## How an alert flows

```text
CloudWatch alarm ──► SNS topic (one per priority, MANAGEMENT account, same region as the alarm,
                       of this environment's alert deployment)
                       └─► alert delivery Lambda of that environment (management account) ──► Slack
```

- Alarm name: `<customer>-<priority>-<alert environment>-<alert-key>`, e.g.
  `acme-P1-prd-https-canary`. The alert environment is in the name so that two environments of one
  customer in the same account and region do not overwrite each other's alarms.
- Alarm description: JSON (`priority`, `customer`, `environment`, `alert_type`, `service`,
  `condition`, `dashboard_url`, `notify`) written by Terraform from the same variables as the
  alarm. The Lambda reads it to build the Slack message; `notify` (`Operations` / `Engineering`)
  picks the channel.
- `alarm_actions` and `ok_actions` both publish to
  `<prefix>-<alert environment>-<region>-alerts-p1/p2/p3` in the management account. This account
  has no SNS topic of its own. The alert environment comes from `environment` (`dev-*` is dev,
  `staging-*` stg, `prod-*` prd, any other name as it is). The ARN is built from
  `management_account_id`, `region`, `alert_topic_name_prefix` and that environment (see
  [`sns.tf`](sns.tf)), so there is nothing to copy from an output. **The management side must have a
  deployment for that environment in this region** (`environment/shr-monitoring`, one workspace per
  environment and region); if it does not, the alarms point at topics that do not exist and fail
  silently. The plan only rejects an alert environment that no deployment can have (more than 13
  characters, or invalid characters). The topic policy takes alarms from any account
  (`modules/alert-delivery`).
- Everything about an alert — priority, audience, wording — is defined once in
  [`alerts.tf`](alerts.tf). To change a priority or a recipient, change it there.

## Usage

```hcl
module "monitoring" {
  source = "../../modules/customer-monitoring"

  customer_code = "acme"
  environment   = "prod-acme"
  region        = "us-east-1"

  # Alerts: the management account whose topics receive the alarms (environment/shr-monitoring)
  management_account_id = "<mgmt>"
  dashboard_url         = "https://grafana.example.com/d/overview?var-customer=acme"

  # What to watch — each group is skipped while its input is null
  instance_id                    = "i-0abc"
  existing_ec2_role_name         = "ec2_role"
  alb_arn_suffix                 = aws_lb.app.arn_suffix
  target_group_arn_suffix        = { app = aws_lb_target_group.app.arn_suffix }
  nlb_arn_suffix                 = aws_lb.vpn.arn_suffix
  nlb_target_group_arn_suffix    = { openvpn = aws_lb_target_group.openvpn.arn_suffix }
  waf_web_acl_name               = aws_wafv2_web_acl.app.name
  acm_certificate_arn            = aws_acm_certificate.app.arn
  https_availability_canary_name = module.canaries.https_availability_canary_name
  synthetics_canary_name         = module.canaries.workflow_canary_name
  backup_monitoring_enabled      = true
}
```

With only the three identity variables the module creates no alarm at all. Each group of alarms
needs its input, and without `management_account_id` the alarms have no notification action.
The customer's budget and cost-anomaly monitor are not in this module: they are kept with the alert topics, in `environment/shr-monitoring` (`cost_customers`, module `modules/cost-monitoring`).

`target_group_arn_suffix` and `nlb_target_group_arn_suffix` are **maps** of `name => suffix` (one entry is fine, at
most 8). The unhealthy-host alarms watch the worst target group, so any group with an unhealthy
host raises them, and the VPN connections alarm adds up the connections of all groups.
The alarm names do not change with the number of groups. Not run against AWS; the metric math
(`MAX([tg1,tg2])`, `SUM([tg1,tg2])`) follows the CloudWatch documentation.

## One apply, with resources created in the same configuration

Terraform must know at plan time whether a group of alarms exists, but the ID of an instance,
ALB or NLB created in the same apply is only known after it exists. Passing such an ID alone
makes `count` fail with "Invalid count argument". Set the matching `enable_*` flag, a plain
`true`, which is known at plan, and pass the ID as usual:

```hcl
module "monitoring" {
  source = "../../modules/customer-monitoring"
  # ...

  instance_id            = aws_instance.lighthouse.id
  existing_ec2_role_name = aws_iam_role.lighthouse.name
  enable_instance_alarms = true

  alb_arn_suffix          = aws_lb.app.arn_suffix
  target_group_arn_suffix = { app = aws_lb_target_group.app.arn_suffix }
  enable_alb_alarms       = true
}
```

Terraform creates the instance and ALB first and the alarms after, because the alarms refer to
their attributes. Flags: `enable_instance_alarms`, `enable_alb_alarms`, `enable_nlb_alarms`,
`enable_waf_alarm`, `enable_certificate_alarms`, `enable_https_canary_alarm`,
`enable_workflow_canary_alarm`. Left null, a group is on when its value is set, as before. The
agent policy is attached to `existing_ec2_role_name` as given, with no lookup at plan time.

## Things to know

- **No topics in this account.** Alarms publish to the management account's topics, so delivery
  failures (`sns-failures`) are watched there, by `modules/alert-delivery`. If `management_account_id`
  is null the alarms are created without notification actions.
- **No budget here.** The budget and cost anomaly monitor of a customer are made centrally by
  `modules/cost-monitoring` (called from `environment/shr-monitoring`), so this module and the CI role that applies
  it need no billing permission.
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
- **Cost:** the budget of this customer filters on the `Instance` tag, which is unique per customer. Its value must
  match the `instance` of this customer in `cost_customers`, and the tag must be active in Billing > Cost
  Allocation Tags. The `cost_center` input only sets the `CostCenter` tag on the alarms.
- **Grafana, one data source for all customers (one account):** every customer is in the same account as the
  monitoring, so one CloudWatch data source reads them all, with the federation role of
  `environment/shr-grafana-federation`. The dashboards choose the customer by its tags (`Customer`,
  `Environment`), so the resources need those tags (`default_tags` on the provider). The Grafana read
  role below is not needed.
- **Grafana, one data source per customer (alternative, switched off):** the per-customer read role (`grafana.tf`,
  `grafana_account_id`, `grafana_role_arn`) is commented out. Dashboards are importable
  JSON, managed in the `graham-infrastructure` repository (a new dashboard goes there);
  `grafana-dashboards/` holds the hand-off copy, with a README on what Grafana needs (pick the
  customer in the **Customer account** dropdown): `env-overview`, `infrastructure`, `remote-access`,
  `application`, `web-protection` and `platform`. Alarm thresholds are drawn on the panels.
  The Infrastructure disk read/write panels (bytes and operations) are dashboard only, with no
  alarm: the first four use the per-instance `AWS/EC2` metrics (Nitro instances only), the
  last four use per-volume `AWS/EBS` metrics, which also work on older instances. The
  firewall, quota and Lambda panels use the same CloudWatch data source (named by its uid in the dashboards); see `environment/shr-grafana-federation`.
