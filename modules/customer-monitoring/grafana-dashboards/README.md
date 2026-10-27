# Grafana dashboards

Six dashboards for the Operations and Engineering teams, as importable Grafana JSON.

**These dashboards are managed in the `graham-infrastructure` repository.** The files here are the
hand-off copy of the first six. A **new dashboard is added to `graham-infrastructure`**, not here.
If you change a dashboard, change it there; this copy is not kept in step automatically.

A dashboard file holds only the layout and the queries. It holds **no data**: the data comes from
the CloudWatch data source in Grafana, which reads the AWS account.

> **One AWS account.** Every customer and the monitoring are in one account, so there is no cross-account link and
> no customer account to pick. The `account` variable and every `accountId` are gone from the six files.
>
> **Region** lists the values of the tag `region` (`Tags.region` of the EC2 instances), so a region that is not supported never shows
> up empty. The list is read in the **default region of the data source**, so it only contains the tag values of the instances
> that live there; a region with no tagged instance in that region is not listed. Default `ap-southeast-2`. The value is both the
> region the CloudWatch call goes to and the value of the tag `region`.
>
> Five dashboards have only three dropdowns: **Region**, **Environment** and **Instance**. Defaults: `ap-southeast-2`,
> `production`, and **All** instances (the value `*`, several instances can also be ticked), so the page opens with every
> instance of that region and environment. Platform has `ap-southeast-2` too; its `environment` stays `prd` (fixed list for the
> Lambda and SNS names).
>
> - `environment` lists the values of the tag `Environment` (`Tags.Environment` of the EC2 instances, default `production`).
>   `instance` lists the values of `Tags.Instance` of the instances of that environment.
> - Every customer panel filters its metric by the dimensions `Environment = $environment`, `Instance = $instance` and
>   `region = $region` (the tag `region`, lowercase; the WAF panels also keep their own `Region` dimension), with
>   `matchExact` off so the metric may have more dimensions (`InstanceId`, `LoadBalancer`, `CanaryName`...). **This assumes the
>   metrics carry the dimensions `Environment`, `Instance` and `region`**: CloudWatch does not add the tags of a resource to its
>   metrics by itself (check with `aws cloudwatch list-metrics`). If they are missing the panels are empty.
> - One line per matching resource (several ALBs or canaries of the same instance show as several lines). The HTTPS and the
>   workflow canary share the tags, so each canary panel shows both until the canary name is told apart.
> - The Network Firewall panel is the shared firewall of the management account: no tag filter, `FirewallName = *`.
> - **Platform** is unchanged: its `environment` is a fixed list (dev, stg, prd) that builds the Lambda and SNS names, and
>   its `customer` textbox is the code of `Lighthouse/Backup`.
>
> Not tried in a live Grafana: the variable queries (`ec2InstanceAttributes`) and the tag dimensions above. The sections below
> that still mention the account, the link, the sink or a resource dropdown describe the older design.

```text
CloudWatch (the one account: monitoring and every customer)
     ▲  Grafana assumes the federation role (Azure Managed Identity)
Data source CloudWatch in Grafana   (one; the customer is picked by tag)
     ▲  the panels query it, with the resources of the chosen customer
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
| **One CloudWatch data source** for the management (monitoring) account | Named in every dashboard by its uid, `8s123msinglish` (there is no data source dropdown; the same one serves the management panels of Platform and Web Protection). Created by hand in the Grafana UI (AWS SDK Default, federation), not by `graham-infrastructure`. The management panels (Platform, Web Protection) follow the **Region** dropdown, so one data source serves every region |
| **Tag dimensions on the metrics** | The metrics of a customer carry the dimensions `Environment`, `Instance` and `region` (the panels filter on them). Not added by CloudWatch on its own |
| The **Environment** and **Region** dropdowns | The formatter Lambda and the alert topics are per environment and region, named `lighthouse-alerting-<environment>-<region>-formatter` and `lighthouse-alerting-<environment>-<region>-alerts-p1/p2/p3`. The Platform panels build those names from the two dropdowns, so there is nothing to type. The environments are `dev`, `stg` and `prd` (the names the module derives from `environment`); another environment name needs its entry added to the `Environment` variable |

The read role is created in this repository (`environment/shr-grafana-federation`): the federation role of that stack
(the Managed Identity of the Grafana Azure VM). It can read the tags the dashboards pick customers by. The IAM user
(`grafana_user_enabled`), the role route (`grafana_account_id`) and the role in each customer account (`modules/customer-monitoring/grafana.tf`)
are commented out.

`graham-infrastructure` only manages the dashboards, and needs no value from this repository: the
dashboards name the data source by its uid (`8s123msinglish`, written in each file: change it there if the data source is made again with another uid). It only
needs those data sources to exist before the panels can show data.

## Conventions

- **Environment** is a choice on every dashboard: the tag value, except on **Platform** (fixed list dev, stg, prd: the Lambda and SNS names are per environment and region). Quota and Network Firewall panels are shared by all environments of a region.
- **Region** is the first choice, then **Environment**, then **Instance**. There is no Data source dropdown: every panel names the data source by its uid, so the dashboards read this one data source.
- Where an alarm exists, its threshold is drawn on the panel (CPU 70 / 90, memory 70 / 85,
  disk 80 / 90, ALB latency 0.3 s, 5xx 5 %, certificate 7 / 30 days, quota 80 / 95 %). Colours
  follow priority: red P1, orange P2, yellow P3.
- Panels with no fixed line have no fixed-threshold alarm: request rate, network, VPN connections,
  WAF and firewall use an anomaly band, and the disk I/O panels have no alarm.
- The Network Firewall, quota, Lambda and SNS delivery panels read the management account. The alert
  topics are in the management account, so the SNS panel uses the same **Data source**, and needs no `accountId`.
- No account ID or ARN is written in any file.

## Not covered by these dashboards

- **AMI snapshot succeeded** stays empty until a job publishes `Lighthouse/Backup` `SnapshotSucceeded`
  (that job is in another repository).
- The HTTPS canary failure reason and an "active alerts" panel are not CloudWatch metrics, so they
  are not panels.
- Certificate days to expiry shows one customer at a time (the customer dropdown).

## Not verified

The dashboards have not been imported into a live Grafana. Check on the first import: the
multi-value `TargetGroup` dimension on Remote Access, the query fields of the CloudWatch panels, and (once the
dashboards are changed) that the tag variables list the resources of the chosen customer and that the panels
return data for them.
