# Grafana dashboards

Six dashboards for the Operations and Engineering teams, as importable Grafana JSON.

**These dashboards are managed in the `graham-infrastructure` repository.** The files here are the
hand-off copy of the first six. A **new dashboard is added to `graham-infrastructure`**, not here.
If you change a dashboard, change it there; this copy is not kept in step automatically.

A dashboard file holds only the layout and the queries. It holds **no data**: the data comes from
the CloudWatch data sources in Grafana, which read the AWS accounts through read-only roles.

```text
CloudWatch (customer account / management account)
     ▲  Grafana assumes a read-only role, then reads metrics
Data source CloudWatch in Grafana   (one per customer, one for the management account)
     ▲  the panels query it
Dashboard (these JSON files)
```

## The dashboards

| File | uid | Title | Panels |
| --- | --- | --- | --- |
| `env-overview.json` | `lighthouse-env-overview` | Lighthouse - Environment Overview | Uptime 24 h / 7 d / 30 d, HTTPS canary, workflow canary |
| `infrastructure.json` | `lighthouse-infrastructure` | Lighthouse - Infrastructure | EC2 status checks, CPU, memory, disk used %, disk read/write (bytes and operations, per instance and per volume), network in/out, CloudWatch agent heartbeat |
| `remote-access.json` | `lighthouse-remote-access` | Lighthouse - Remote Access | NLB healthy targets, active VPN connections, new connections per hour (several OpenVPN target groups can be selected) |
| `application.json` | `lighthouse-application` | Lighthouse - Application | HTTPS canary, ALB response time p95, request rate, 5xx rate, healthy targets, workflow canary |
| `web-protection.json` | `lighthouse-web-protection` | Lighthouse - Web Protection | WAF allowed vs blocked, blocked by rule group, Network Firewall passed vs dropped, certificate days to expiry |
| `platform.json` | `lighthouse-platform` | Lighthouse - Platform | Quota usage %, AMI snapshot succeeded, Lambda errors and throttles, SNS delivery failures |

The `uid` and the title carry a `lighthouse` prefix so they do not collide with dashboards that
already exist in a shared Grafana: an import with an existing `uid` overwrites that dashboard, and
Grafana refuses two dashboards with the same title in one folder. Check the target Grafana for these
six `uid` values anyway before importing. No file has a top-level `id`, and nothing in this
repository refers to a dashboard `uid`; the `dashboard_url` in the alert messages is a link you set.

## What Grafana needs for them to work

| Needed | Detail |
| --- | --- |
| A **CloudWatch data source per customer** | Its name appears in the **Customer** dropdown. Set `Assume Role ARN` to the `grafana_role_arn` output of the customer's environment, and the External ID |
| A **CloudWatch data source for the management account** | Chosen in the **Management account** dropdown (Platform and Web Protection). `Assume Role ARN` is the `grafana_role_arn` output of `environment/shr-monitoring`. Its default region must be the region of the formatter Lambda: the management panels use the data source's default region |
| The **Formatter Lambda** textbox on Platform | Defaults to `lighthouse-alerting-formatter`; change it if the Lambda is renamed |

The roles are created in this repository (`modules/customer-monitoring/grafana.tf` and
`modules/alert-formatter/grafana.tf`) when `grafana_account_id` and `grafana_external_id` are set.
Both values are shown on the CloudWatch data source page of Grafana ("How to create an IAM role
for grafana to assume"). Without them, no role exists.

Values to hand over to `graham-infrastructure`:

| Value | Where it comes from |
| --- | --- |
| Customer role ARN | `terraform output grafana_role_arn` in the customer environment |
| Management role ARN | `terraform output grafana_role_arn` in `environment/shr-monitoring` |
| Customer region | the `region` variable of that environment |
| Account ID of Grafana, External ID | the Grafana CloudWatch data source page |

## Conventions

- The **Customer** dropdown is a data source variable: choosing a customer selects its data source.
  Most CloudWatch metrics have no customer dimension.
- Where an alarm exists, its threshold is drawn on the panel (CPU 70 / 90, memory 70 / 85,
  disk 80 / 90, ALB latency 0.3 s, 5xx 5 %, certificate 7 / 30 days, quota 80 / 95 %). Colours
  follow priority: red P1, orange P2, yellow P3.
- Panels with no fixed line have no fixed-threshold alarm: request rate, network, VPN connections,
  WAF and firewall use an anomaly band, and the disk I/O panels have no alarm.
- The Network Firewall, quota, Lambda and SNS delivery panels read the management account. The alert
  topics are in the management account, so the SNS panel uses the **Management account** data source.
- No account ID or ARN is written in any file.

## Not covered by these dashboards

- **AMI snapshot succeeded** stays empty until a job publishes `Lighthouse/Backup` `SnapshotSucceeded`
  (that job is in another repository).
- The HTTPS canary failure reason and an "active alerts" panel are not CloudWatch metrics, so they
  are not panels.
- Certificate days to expiry shows one customer at a time (the Customer dropdown).

## Not verified

The dashboards have not been imported into a live Grafana. Check on the first import: the
multi-value `TargetGroup` dimension on Remote Access, and the query fields of the CloudWatch panels.
