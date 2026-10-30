# grafana-datasources

> **The route chosen: federation with the Managed Identity of the Grafana Azure VM** (section *Grafana on an Azure VM*
> below): no IAM user and no key. This stack and the files in `json/` and `provisioning/` are for a Grafana that
> assumes a role in the AWS account (`grafana_account_id`, commented out in the AWS code). The data source of the chosen
> route is made by hand in the Grafana UI.

Lets Grafana read CloudWatch. **Every customer and the monitoring live in one AWS account, so one CloudWatch
data source for that account reads everything.** The customer is picked in the dashboards by tag (`Customer`,
`Environment`), not by account. One data source per customer (`customers`) is still possible, as an alternative
for customers in other accounts.

```text
CloudWatch (the one account: monitoring and every customer)
     ▲  Grafana assumes the federation role (token of its Managed Identity)
Data source CloudWatch in Grafana   (created by hand in the UI)
     ▲  the panels query it, with the instance, load balancer... of the customer chosen by tag
Dashboards  (graham-infrastructure)
```

The customer accounts need **no Grafana role** and no link. The AWS side, in order:

1. `environment/shr-monitoring`, one deployment per environment and region. The read access for Grafana is a
   separate stack, `environment/shr-grafana-federation` (one role for the whole account): note its output
   `grafana_federated_role_arn`.
2. The CloudWatch data source in Grafana, by hand, with AWS SDK Default (see the section below).

The data source's default region is one region; the dashboards have a **Region** dropdown for the others.

This is the only Grafana step needed to read CloudWatch. Watching the alert pipeline from Grafana
(alert rules) is a separate stack, [`../grafana-alerting`](../grafana-alerting/README.md),
for later: it needs this stack's management data source only for its own rules.

## What this stack creates

| Resource | Meaning |
| --- | --- |
| `grafana_data_source.cloudwatch_management` | The management account's data source (uid `lighthouse-cw-management`), only when `management_grafana_role_arn` is set. **With one account this is the only data source needed** |
| `grafana_data_source.customer` | Alternative: one data source per entry of `customers` (leave it empty with one account), named by the key. It assumes the read-only role of that customer account. The dashboards list these in their **Data source** dropdown |

It creates no AWS resource. The roles it assumes come from the AWS stacks (step 3 and 4 below).

## Grafana on an Azure VM: federation with its Managed Identity (recommended, no key)

When the Grafana server runs on an **Azure VM** (its Azure data source uses `azureAuthType: msi`), it can get
temporary AWS credentials with no access key: OIDC federation. The Managed Identity of the VM proves who it is to AWS,
AWS lets that one identity assume a read-only role (`AssumeRoleWithWebIdentity`), and the Grafana data source uses
**AWS SDK Default**. Not run yet: try it in a test setup first.

| # | What | Who |
| --- | --- | --- |
| 1 | Attach a **user-assigned Managed Identity** to the VM; note its **object (principal) ID** (`grafana_azure_subject`) and the **tenant ID** (`grafana_azure_tenant_id`) | Azure owner |
| 2 | Choose the **audience**: an Entra app registration made for AWS with an Application ID URI, for example `api://aws-sts` (`grafana_azure_audience`) | Azure owner |
| 3 | Stack [`environment/shr-grafana-federation`](../shr-grafana-federation/README.md): put the three values in its `terraform.tfvars` and apply. It creates the OIDC provider for `https://sts.windows.net/<tenant>/` and the role `lighthouse-alerting-grafana-federated`, which trusts only that subject and audience and has the read-only policy. Note the output `grafana_federated_role_arn` | AWS admin |
| 4 | On the VM, a timer (about every 30 minutes) asks the Azure metadata service for a token for that audience and writes it to a file the Grafana user can read (write a temporary file, then rename it) | Someone on the VM |
| 5 | Give the Grafana service the environment variables `AWS_ROLE_ARN` (the output of step 3), `AWS_WEB_IDENTITY_TOKEN_FILE` (the file of step 4) and `AWS_REGION`, and restart it | Someone on the VM |
| 6 | Data source CloudWatch: Authentication Provider **AWS SDK Default**, Assume Role ARN empty, then **Save & test** | You |

Token request of step 4 (idea, to adapt):

```bash
curl -s -H "Metadata:true" \
  "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=<audience>&client_id=<client id of the Managed Identity>" \
  | jq -r .access_token > /var/run/aws/azure-token.tmp && mv /var/run/aws/azure-token.tmp /var/run/aws/azure-token
```

Not verified: the audience rules when asking for a Managed Identity token (whether the app registration of step 2 is
needed), how AWS handles the `sts.windows.net` issuer of v1 tokens, the condition keys `sts.windows.net/<tenant>/:aud`
and `:sub` of the role trust, and that the Grafana data source reads `AWS_WEB_IDENTITY_TOKEN_FILE` on an Azure VM.

## First check: does the Grafana server have an AWS identity?

Add a CloudWatch data source with **AWS SDK Default**, no Assume Role ARN, and press **Save & test**. An error
`no EC2 IMDS role found ... ec2imds ... StatusCode: 400` means the Grafana server has **no AWS identity**:
the route below (AWS SDK Default, then assume a role) cannot work. Use the federation route above.

## IAM user with an access key (switched off)

The IAM user route (`grafana_user_enabled`, output `grafana_user_name`, in `modules/alert-delivery/grafana.tf`) is
commented out. It stays as a fallback if the federation does not work: remove the comment markers to bring it back;
the data source then uses Access & secret key and the key is made by hand (`aws iam create-access-key`), so it never
enters the Terraform state.

## The route when the server has an AWS identity: AWS SDK Default

The Grafana server signs in with the AWS identity it already has (the role of its machine or task) and
assumes the read-only role of each customer. Nothing secret is given to Grafana. What it needs:

| Element | Where it comes from |
| --- | --- |
| An AWS identity on the Grafana server | The role attached to its machine, task or pod. Nothing to create if it already runs in AWS with a role |
| The account of that identity (`grafana_account_id`) | `aws sts get-caller-identity` on the Grafana server, field `Account` |
| Permission to assume the roles | Add to the policy of that identity: `sts:AssumeRole` on `arn:aws:iam::*:role/*-monitoring-grafana-read` |
| The customer role | `terraform output grafana_role_arn` of the customer stack, after applying it with `grafana_account_id` |
| Terraform route | `authentication_provider = "default"` (this stack's default) |
| File route | `authType: default` in [provisioning/cloudwatch.yaml](provisioning/cloudwatch.yaml) |

If the Grafana server runs **outside AWS** it has no identity to start from: this route does not apply.

## Does Grafana need an AWS profile?

Not on Grafana Cloud. A **profile** (a named entry of an AWS credentials file) is how a Grafana that you
run yourself, with AWS credentials on its server, signs in. Grafana Cloud has no such file, and you
give it no key: its data source has an authentication provider, **Grafana Assume Role**, in which
Grafana itself, from its own AWS account, assumes the read-only role in yours. The trust policy of that
role (created by the AWS stacks) allows exactly that account, nothing else. That is why steps 2 and 3
below need Grafana's account ID, and why there is no access key anywhere.

This stack sets it in `authentication_provider`: `default` (the default here: AWS SDK Default, a Grafana you
run yourself whose server has an AWS identity) or `grafana_assume_role` (Grafana Cloud only). The role's trust
policy trusts the account you give as `grafana_account_id`: for `default` that is the account of the Grafana
server, for `grafana_assume_role` it is the account Grafana Cloud shows.

## A Grafana you run yourself (an address that is not `grafana.net`)

A Grafana on your own domain (for example `grafana.mycompany.com`), even one open to anonymous viewers, is
not Grafana Cloud. There is **no Grafana account ID to look up**: nobody issues one. It changes meaning:

| Value | What it is | How to get it |
| --- | --- | --- |
| `grafana_account_id` (in the AWS stacks) | The **AWS account the Grafana server runs in** (EC2, ECS task, EKS pod...) | `aws sts get-caller-identity` on that server, or ask who runs it |

How it works: the Grafana server signs in with the AWS identity it already has (the role attached to its
machine or task, or a profile) and assumes the read-only role of each customer. Two sides must allow it:

1. **The customer role** (created by the AWS stacks) trusts the account of the Grafana server. This is the
   existing trust policy.
2. **The identity of the Grafana server** needs permission to assume the roles, in its own policy:

   ```json
   { "Effect": "Allow", "Action": "sts:AssumeRole",
     "Resource": "arn:aws:iam::*:role/*-monitoring-grafana-read" }
   ```

   (and the management role, `lighthouse-alerting-<region>-grafana-read`, if you use it).

In this stack `authentication_provider = "default"` is the default. Everything else (steps 3 to 7 below) is the same. If the Grafana server is **not in
AWS** it has no AWS identity to start from; then it needs an access key of a user allowed to assume the
roles, which this stack does not set up yet.

The trust policy trusts the whole account of the Grafana server (`arn:aws:iam::<account>:root`). If other
things run in that account, narrow it to the role of the Grafana server.

## JSON files and a loader for another repository

If the data sources and dashboards are managed in another repository (`graham-infrastructure`), [`json/`](json/README.md)
has the data sources as JSON files in the format of the Grafana HTTP API and a PowerShell script
(`load-grafana.ps1`) that creates or updates them, and the dashboards too, with `-DryRun` to preview.

## A provisioning file instead of Terraform

If you run Grafana yourself and can put a file on its server, [`provisioning/cloudwatch.yaml`](provisioning/cloudwatch.yaml)
defines the same data sources without Terraform. It does not work on Grafana Cloud, which does not read
provisioning files. Use **one** of the two for a given data source (same `uid`), never both.

1. Note the AWS account the Grafana server runs in.
2. Apply the customer's stack with `grafana_account_id` = that account: it creates the read-only role. Note `terraform output grafana_role_arn`.
3. Let the identity of the Grafana server assume the role (`sts:AssumeRole`, see above).
4. Edit the file: one entry per customer (name, `uid`, the role ARN, the default region), and
   `authType` for how your Grafana signs in.
5. Put the file in `/etc/grafana/provisioning/datasources/` (with Docker, mount it there) and restart Grafana,
   or reload it with `POST /api/admin/provisioning/datasources/reload`.
6. In Grafana, open each data source and press **Save & test**.

## Order of work

1. **Grafana Cloud stack** (by hand, once). Create it and note its URL.
2. **The value the AWS roles need** (by hand, once): the AWS account the Grafana server runs in (`aws sts get-caller-identity`
   on it). On Grafana Cloud, Grafana shows its **AWS account ID** at Connections, Data sources, Add data source,
   **CloudWatch** (do not save the data source there).
3. **A read-only role in each customer account.** In the customer's environment
   (`dev-cus0001`, `stg-customer`, `prd-customer`) set `grafana_account_id`, then apply. With the other inputs null the module creates only that role
   (and nothing else for monitoring). Note `terraform output grafana_role_arn`.
4. **Management account (optional).** The role comes from `modules/alert-delivery`, which means a
   `shr-monitoring` deployment with `grafana_account_id` set (see its README).
   Skip it to read only the customers' CloudWatch.
5. **A Grafana service account and token** (by hand, once), allowed to manage data sources. **Optional**: skip it when Grafana lets everyone in as Admin; the stack then uses the provider's `anonymous` setting. Check first with `curl.exe -s <grafana url>/api/datasources` (a JSON list means no token is needed; `401` means create one). With a token, `$env:TF_VAR_grafana_token` below.
6. **This stack:**

   ```powershell
   cd environment\grafana-datasources
   Copy-Item terraform.tfvars.example terraform.tfvars   # fill in grafana_url and customers
   $env:TF_VAR_grafana_token = "<service account token>"   # skip when Grafana needs no token
   terraform init
   terraform plan        # read it first
   terraform apply
   ```

7. **Check:** in Grafana open each data source and press **Save & test**: "Data source is working". Or
   open Explore, choose the data source, and query a metric.

To add a customer in the same account: tag its resources (`Customer`, `Environment`) and apply its stack. Nothing
changes here. To add a customer in another account with a data source of its own (the alternative): apply the
customer's stack with the Grafana variables (step 3), add one entry to `customers`, apply this stack.

```hcl
customers = {
  acme = { account_id = "222222222222", environment = "prod-acme", region = "ap-southeast-2" }
}
```

## Not verified (written from documentation, nothing was run)

- **Picking a customer by tag** (the `Customer` and `Environment` variables of the dashboards): written from the
  Grafana documentation, never run. Check in Grafana that the variable lists the tagged resources of the customer
  and that a panel returns data for it.
- **`terraform validate` was not run**: the provider could not be loaded where this was written. Attribute
  names follow the provider's documentation; pin the provider version after you validate.
- That `grafana_assume_role` is the right `authType` value for the provider and for your Grafana version
  (taken from the Grafana documentation of the Grafana Assume Role provider, not run). If the apply rejects
  it, create one data source by hand in the UI with the provider **Grafana Assume Role**, open its JSON in
  the API, and use the `authType` it shows.
- That the customer role ARN built from the naming rule `<environment>-monitoring-grafana-read` matches the
  role that `modules/customer-monitoring` creates. If a role has another name, set `role_arn` for that
  customer.
