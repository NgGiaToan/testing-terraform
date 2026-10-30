# JSON files for the data sources and the dashboards

> **Not used on the route chosen** (the data source is made by hand in the Grafana UI with AWS SDK Default, through federation):
> these files are for the role route, which is commented out in the AWS code. See [`../README.md`](../README.md).

For the repository that manages the Grafana data sources and dashboards (`graham-infrastructure`):
the data sources as JSON files, in the format of the Grafana HTTP API, and a script that loads them.
The six dashboards are already JSON files, in
[`modules/customer-monitoring/grafana-dashboards`](../../../modules/customer-monitoring/grafana-dashboards).
Copy what you need to the other repository. Use **one** way to manage a given data source (these files, the
Terraform in the folder above, or the provisioning file), never two.

| File | What it is |
| --- | --- |
| `datasources/management.example.json` | The management (monitoring) account's data source. **With one account this is the only one you need**: copy it as `datasources/management.json`. The customers are read through it, picked by tag |
| `datasources/customer.example.json` | Alternative: one customer's own CloudWatch data source. Copy it as `datasources/<customer>.json` and fill it in. Not needed with one account |
| `load-grafana.ps1` | Creates or updates the data sources (and the dashboards) through the Grafana API. Safe to run again |

The loader skips `*.example.json`, so a placeholder is never loaded by mistake.

## What the fields mean (the route chosen: AWS SDK Default)

| Field | Value |
| --- | --- |
| `name` | The name shown in the **Data source** dropdown of the dashboards (the management one: `CloudWatch - management account`; a customer one: the customer's name) |
| `uid` | `lighthouse-cw-<name>` (`lighthouse-cw-management` for the management one). Keep it stable: it identifies the data source |
| `type` / `access` | `cloudwatch` / `proxy`: the Grafana server runs the queries, with its own AWS identity |
| `jsonData.authType` | `default`: AWS SDK Default, the AWS identity of the Grafana server (the role of its machine or task) |
| `jsonData.assumeRoleArn` | The management one: `terraform output grafana_role_arn` of `shr-monitoring` (`arn:aws:iam::<management account>:role/lighthouse-alerting-<region>-grafana-read`). A customer one: `grafana_role_arn` of the customer's stack |
| `jsonData.defaultRegion` | The region of the customer's resources |

## Load them

```powershell
# GRAFANA_TOKEN is optional: without it no Authorization header is sent (a Grafana that lets everyone in
# as Admin).
$env:GRAFANA_TOKEN = "<service account token that may manage data sources and dashboards>"

# 1. See what would happen, without touching Grafana
.\load-grafana.ps1 -GrafanaUrl https://grafana.mycompany.com -DryRun

# 2. Data sources only
.\load-grafana.ps1 -GrafanaUrl https://grafana.mycompany.com

# 3. Data sources and dashboards (the folder holds the six dashboard files)
.\load-grafana.ps1 -GrafanaUrl https://grafana.mycompany.com -DashboardsPath ..\dashboards -FolderUid <folder uid, optional>
```

Then in Grafana open each data source and press **Save & test**. Before that, the AWS side must be in place
(see [`../README.md`](../README.md)): the read-only role (the federation role of `environment/shr-grafana-federation`,
or one created with `grafana_account_id`), and permission for the AWS identity of the Grafana server to use it.

The loader drops the numeric `id` and the `version` of a dashboard before sending it (they belong to one Grafana),
and replaces a dashboard with the same `uid`.

## If the other repository uses Terraform

Read the same files from Terraform instead of using the loader:

```hcl
locals {
  acme = jsondecode(file("${path.module}/datasources/acme.json"))
}

resource "grafana_data_source" "acme" {
  type = local.acme.type
  name = local.acme.name
  uid  = local.acme.uid

  json_data_encoded = jsonencode(local.acme.jsonData)
}
```

## Not verified

Nothing here was run against a Grafana. The script was only syntax-checked and run with `-DryRun`.
- The field names of the CloudWatch data source (`authType`, `assumeRoleArn`, `defaultRegion`) follow the
  Grafana documentation. Create one data source by hand, read it with `GET /api/datasources/uid/<uid>`, and compare.
- That `PUT /api/datasources/uid/<uid>` accepts the same body as the creation call, and that
  `POST /api/dashboards/db` accepts these dashboards on your Grafana version. If a call is refused, the message
  names the field.
