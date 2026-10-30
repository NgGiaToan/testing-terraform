# shr-grafana-federation

The AWS side of letting **Grafana, running on an Azure VM, read CloudWatch with no access key**: an OIDC provider
that trusts Microsoft Entra ID, and one read-only role that only the Managed Identity of the Grafana VM can assume
(`AssumeRoleWithWebIdentity`). The VM then gets temporary credentials and nothing long-lived is stored anywhere.

```text
Grafana (Azure VM, Managed Identity) ──► token ──► AWS STS ──► temporary credentials of the role
                                                                      │ read only
                                                                      ▼
                                              CloudWatch of this account (monitoring and every customer)
```

The connection is one way: Grafana reads AWS. AWS gets no access to Azure, and no network link is built (Grafana calls
the public AWS endpoints on port 443).

## Why its own stack

IAM is global: one OIDC provider and one role serve the whole account, whatever the environment or the region. They
used to live in `environment/shr-monitoring`, which runs once per environment and region, so they had to be turned on
in one deployment only. Here there is **one deployment, one state, no workspace**. Account-level IAM, applied once by an
admin, like `shr-iam`: not from CI.

## What it creates

| Resource | Meaning |
| --- | --- |
| `aws_iam_openid_connect_provider.azure` | Trusts tokens of `https://sts.windows.net/<tenant>/` for the chosen audience |
| `aws_iam_role.grafana` (`lighthouse-alerting-grafana-federated`) | The role the VM assumes. Its trust accepts **one** subject and **one** audience |
| `aws_iam_role_policy.read` | Read only: CloudWatch, resource discovery by tag (`tag:GetResources`, `ec2:DescribeInstances`, `ec2:DescribeRegions`) so the dashboards can pick a customer by its tags, and `logs:DescribeLogGroups` that Grafana's Save & test calls |

## The three values (none is a secret)

| Variable | What | Where to get it |
| --- | --- | --- |
| `grafana_azure_tenant_id` | The Entra tenant (GUID) | Entra ID, Overview; `az account show --query tenantId -o tsv` |
| `grafana_azure_subject` | Object (principal) ID of the Managed Identity attached to the Grafana VM | Identity of the VM, Overview; `az vm show ... --query identity`; or a read of the token's `sub` or `oid` on the VM |
| `grafana_azure_audience` | The Application ID URI of an Entra app registration made for AWS, e.g. `api://aws-sts` | Created by whoever manages Entra; you choose the string |

Put them in `terraform.tfvars` (copy `terraform.tfvars.example`). This stack has one deployment, so `terraform.tfvars` is
loaded automatically. They are identifiers, not credentials, so the file can be committed to a private repository.
The audience must match the `aud` claim of the token that the VM requests, **character by character**, and the subject
the `sub` claim: check them on the VM before applying (see below).

## Apply (an admin)

```powershell
cd environment\shr-grafana-federation
Copy-Item terraform.tfvars.example terraform.tfvars   # fill in the three values
terraform init
terraform plan        # read it first
terraform apply
terraform output grafana_federated_role_arn
```

`terraform init` writes `.terraform.lock.hcl`: commit it, so everybody uses the same provider version.

## What happens next (not in this stack)

| Step | Who |
| --- | --- |
| On the VM: a timer asks the Azure metadata service for a token for the audience and writes it to a file the Grafana user can read; set `AWS_ROLE_ARN` (the output above), `AWS_WEB_IDENTITY_TOKEN_FILE` and `AWS_REGION` for the Grafana process; restart it | Someone on the VM |
| In Grafana: a CloudWatch data source with **AWS SDK Default**, Assume Role ARN empty, then Save & test | You |

The details, a sample token script and the troubleshooting table are in
[`../grafana-datasources/README.md`](../grafana-datasources/README.md), section *Grafana on an Azure VM*.

Check the claims of a token on the VM (never paste the token itself anywhere):

```bash
cut -d. -f2 /run/aws-web-identity/token | tr '_-' '/+' | base64 -d 2>/dev/null | jq '{iss, aud, sub, tid}'
```

`iss` must be `https://sts.windows.net/<tenant>/`, `aud` the audience, `sub` the subject, `tid` the tenant.

## Not verified (written from documentation, nothing was run)

- `terraform validate` was not run: the provider could not be loaded where this was written. Run `terraform init`,
  `terraform validate` and read the plan before the first apply.
- How AWS handles the `sts.windows.net` issuer of v1 tokens (the Managed Identity tokens), and that the condition keys of
  the trust are `sts.windows.net/<tenant>/:aud` and `:sub`.
- The audience rules when a Managed Identity asks for a token (whether the app registration is needed).
- That the Grafana CloudWatch data source (AWS SDK Default) reads `AWS_WEB_IDENTITY_TOKEN_FILE` on an Azure VM.
