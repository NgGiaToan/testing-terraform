# grafana-alerting

> **NOT APPLIED YET, NOT VALIDATED.** The code is live (`rules.tf`, `datasource.tf`, `variables.tf`) but nothing was run:
> `terraform validate` was not run (see *Not verified* below). For Grafana to read CloudWatch, use
> `environment/grafana-datasources`.

The Grafana half of the watch on the AWS alert pipeline: Grafana reads the CloudWatch metrics of the management
account and tells you in Slack when the pipeline breaks.

```text
        alerts on the pipeline
 Grafana ───────────────────────► Slack
   ▲  reads CloudWatch metrics of
   │  the Lambdas and SNS topics
 AWS (management account)
```

| If this breaks | who tells you | how |
| --- | --- | --- |
| CloudWatch, SNS or the alert delivery Lambda | **Grafana** | rules in `rules.tf` read the metrics of each environment's Lambda and topics (`alert_environments`) and post to your Slack contact point |

Everything else (the customer alerts) stays on CloudWatch, SNS and the Lambda.

**There is no heartbeat.** Watching Grafana itself from AWS (a heartbeat that Grafana publishes to SNS, and an alarm
when it stops) is out of scope: Grafana runs on an Azure VM. So if Grafana stops, nobody is told that these rules
are no longer watching.

## What this stack creates

| File | Resource | Meaning |
| --- | --- | --- |
| `datasource.tf` | `grafana_folder.lighthouse` | Folder for the rules. The CloudWatch data sources are **not** created here: see `environment/grafana-datasources` |
| `rules.tf` | `grafana_rule_group.pipeline_health` | Per environment in `alert_environments` (default dev, stg, prd): alert delivery Lambda errors, alert delivery Lambda throttles, and delivery failures of the P1, P2 and P3 topics (5 rules each): 15 rules by default. They go to your existing Slack contact point |

The notification policy tree is **not** managed here: the resource for it replaces the whole tree,
which would erase the routes you already have. The rules choose their contact point themselves.

## Data sources and dashboards

The **data sources** (the management account's and one per customer) are created by
[`../grafana-datasources`](../grafana-datasources/README.md), which is the first Grafana step and the
only one needed to read CloudWatch from Grafana. **Apply it before this stack**: the rules read the
management data source by its uid (`management_data_source_uid`, default `lighthouse-cw-management`,
the uid that stack gives it when `management_grafana_role_arn` is set there). The **dashboards** are
managed in the `graham-infrastructure` repository; they name the data source by its uid (written in each dashboard).

## Grafana Cloud cannot load provisioning files

Grafana's documentation says provisioning with configuration files is not available on Grafana
Cloud. That is why this is Terraform (the "files" are these `.tf` files). It talks to the Grafana
API with a service account token.

## Order of work

1. **AWS.** Apply `environment/shr-grafana-federation` once (the role Grafana assumes to read CloudWatch), then
   `environment/shr-monitoring` for each environment and region you want watched (one workspace
   `<environment>-<region>` each). `alert_environments` of this stack must name deployments
   that exist.
2. **Grafana.** First create the management CloudWatch data source by hand in the Grafana UI with AWS SDK Default
   (federation), with the uid `lighthouse-cw-management` (the stack `environment/grafana-datasources` is for the role
   route, switched off). Create a service account and a token. Copy `terraform.tfvars.example` to `terraform.tfvars`,
   fill in the values, and pass the token as an environment variable (`TF_VAR_grafana_token`). Then
   `terraform init`, `validate`, `plan`, `apply`. Read the plan first.

## Test

Temporarily make an environment's alert delivery Lambda fail (for example clear that environment's webhook secret value)
and send a test alert; Grafana's `Alert delivery Lambda (<environment>): errors` rule should post to Slack within a
few minutes. Restore the secret afterwards.

## Not verified (written from documentation, nothing was run)

- The Terraform provider could not be loaded where this was written, so **`terraform validate` was
  not run**. Attribute names follow the provider's documentation; pin the provider version after you
  validate.
- The CloudWatch query model JSON of the rules (the same format as the dashboards in
  `modules/customer-monitoring/grafana-dashboards`).
- That the rules find the management data source by the uid `lighthouse-cw-management`, which
  `environment/grafana-datasources` gives it (its own README lists what is not verified about the data
  sources).

## Limits to keep in mind

- If Grafana stops, or its token file on the VM is not refreshed, the rules stop with it and nobody is told.
- An environment in `alert_environments` that has no deployment has no metrics, and "no data" counts
  as OK, so it raises **no alert**: a deployment that was never applied is not noticed.
- This stack reads one `region`. Deployments in other regions need another run of this stack (or a
  change to it).
