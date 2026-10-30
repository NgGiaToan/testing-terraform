# ngcs-metrics-server-roles

Ansible role `config`: configures Grafana on the metrics server.

- Renders the provisioning file for the data sources
  ([config/templates/datasources.yaml.j2](config/templates/datasources.yaml.j2)): Prometheus, Azure Monitor and
  AWS CloudWatch (`cloudwatch_enabled`), and reloads Grafana.
- Gives the Grafana service an AWS identity, so that the CloudWatch data source works without an access key
  (`aws_federation_enabled`, [config/tasks/aws_federation.yml](config/tasks/aws_federation.yml)).

## How CloudWatch gets its AWS access

```text
Azure instance metadata service
      │  token of the Managed Identity, audience api://aws-sts      (grafana-aws-token.timer, every 30 min,
      ▼                                                              /usr/local/bin/grafana-aws-token.sh)
/run/aws-web-identity/token   (root:grafana, 0640)
      │  AWS_WEB_IDENTITY_TOKEN_FILE + AWS_ROLE_ARN + AWS_REGION    (drop-in of the Grafana service)
      ▼
Grafana, data source CloudWatch (authType: default = AWS SDK Default)
      │  sts:AssumeRoleWithWebIdentity
      ▼
role lighthouse-alerting-grafana-federated  ──►  CloudWatch of the AWS account (monitoring and every customer)
```

The data source itself says only `authType: default`. The link with the OIDC setup is these environment variables
of the service: the AWS SDK sees them and does the exchange. The AWS side (OIDC provider, role, read-only policy)
is the stack `environment/shr-grafana-federation` of terraform-pipeline-test.

What the role puts on the server:

| Path | What |
| --- | --- |
| `/usr/local/bin/grafana-aws-token.sh` | Asks Azure for the token, writes a temp file and renames it |
| `/etc/systemd/system/grafana-aws-token.service` and `.timer` | Runs the script at boot (1 min) and every `aws_token_refresh` |
| `/etc/systemd/system/grafana-server.service.d/aws-federation.conf` | The three AWS variables, and `Wants/After` the token service so a token exists before Grafana starts |
| `/etc/grafana/provisioning/datasources/datasources.yaml` | The data sources |

The role checks before it touches Grafana (all in [config/tasks/aws_federation.yml](config/tasks/aws_federation.yml)),
and stops with a message if one fails, so a running Grafana is left alone:

1. It runs the token service once (the log of the service is shown if it fails).
2. The token file exists, is not empty and belongs to the Grafana group.
3. The claims of the token: `aud` equals `azure_audience`, `iss` is `https://sts.windows.net/<tenant>/`, and `sub`
   equals `azure_mi_object_id` when you set it.
4. AWS STS accepts the token for `aws_role_arn` (`aws_sts_check_enabled`): the call Grafana's AWS SDK will make.

Only then the drop-in with the three AWS variables is written, and the handlers restart Grafana at the end of the play.

## Values passed in from outside

The role has no real values inside it. These must be passed in, and the role stops at the first task with a
clear message if one is missing:

| Variable | Meaning |
| --- | --- |
| `prometheus_url`, `prometheus_version`, `prometheus_uid` | Prometheus data source |
| `azure_subscription_id`, `azure_monitor_uid` | Azure Monitor data source |
| `cloudwatch_default_region` | Default region of the CloudWatch data source (needed when `cloudwatch_enabled`) |
| `aws_role_arn` | Output `grafana_federated_role_arn` of `shr-grafana-federation` (needed when `aws_federation_enabled`) |
| `azure_mi_client_id` | Client ID of the Managed Identity of the VM (needed when `aws_federation_enabled`) |
| `azure_audience` | Audience of the token, same as `grafana_azure_audience` in the AWS stack (needed when `aws_federation_enabled`) |
| `grafana_admin_password` | To reload Grafana; Ansible Vault or the environment |

Optional, with a default in [config/defaults/main.yml](config/defaults/main.yml): `cloudwatch_enabled`,
`cloudwatch_uid`, `cloudwatch_assume_role_arn`, `aws_federation_enabled`, `aws_region`, `aws_token_file`,
`aws_token_refresh`, `azure_mi_object_id` (recommended: the `sub` the token must have), `aws_sts_check_enabled`,
`grafana_url`, `grafana_admin_user`, `grafana_service_name`, `grafana_group`,
`grafana_provisioning_dir`. Keep a uid that already exists in Grafana unchanged.

Ways to pass them, from the highest precedence down:

```bash
# 1. Command line / CI job
ansible-playbook site.yml -e cloudwatch_default_region=ap-southeast-2 -e @vars.yml

# 2. A vars file (with the secret in Ansible Vault)
ansible-playbook site.yml -e @vars.yml --ask-vault-pass

# 3. group_vars/grafana.yml next to the inventory, loaded automatically

# 4. The environment, read with lookup('ansible.builtin.env', ...), see examples/playbook.example.yml
GRAFANA_ADMIN_PASSWORD=... ansible-playbook site.yml
```

Where each value comes from is written next to it in [examples/vars.example.yml](examples/vars.example.yml);
the playbook is [examples/playbook.example.yml](examples/playbook.example.yml).

## Setup, in order

| # | What | Who / where |
| --- | --- | --- |
| 1 | Attach a user-assigned **Managed Identity** to the Grafana VM. Note its **client ID** (`azure_mi_client_id`), **object ID** (`azure_mi_object_id`, `grafana_azure_subject`) and the **tenant ID** | Azure owner |
| 2 | Make an **Entra app registration** for AWS with an Application ID URI (`azure_audience`, `grafana_azure_audience`). If the tenant refuses `api://aws-sts`, use `api://<app id>` | Azure owner |
| 3 | **Look at the claims of a token on the VM** (below) and write down `iss`, `aud`, `sub`, `tid` | On the VM |
| 4 | Apply `environment/shr-grafana-federation` of terraform-pipeline-test with the values of step 3; note `grafana_federated_role_arn` (`aws_role_arn`) | AWS admin |
| 5 | Fill in the variables ([examples/vars.example.yml](examples/vars.example.yml)) and the inventory ([examples/inventory.example.ini](examples/inventory.example.ini)) | You |
| 6 | Run the role (below). Add `-vvv` only if you must: the token never appears in the output (`no_log`) | You |
| 7 | Grafana, data source CloudWatch, **Save & test**; then the checks of the next section | You |

Claims of a token, on the VM (never paste the token itself anywhere):

```bash
TOKEN=$(curl -s -H "Metadata:true" -G "http://169.254.169.254/metadata/identity/oauth2/token" \
  --data-urlencode "api-version=2018-02-01" --data-urlencode "resource=<azure_audience>" \
  --data-urlencode "client_id=<azure_mi_client_id>" | jq -r .access_token)
echo "$TOKEN" | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq '{iss, aud, sub, tid}'
```

`iss` must be `https://sts.windows.net/<tenant>/` (with the last `/`), `aud` the audience, `sub` the object ID.
`AADSTS500011` means the app registration of step 2 does not exist or the Application ID URI is not the one you asked for.

## Run

```bash
cd ngcs-metrics-server-roles            # ansible.cfg here makes `role: config` found
ansible-playbook -i <inventory> examples/playbook.example.yml --syntax-check
ansible-playbook -i <inventory> examples/playbook.example.yml -e @<vars file>
```

The playbook:

```yaml
- hosts: grafana
  become: true
  roles:
    - role: config
```

`--check` cannot pass on a first run: the token is not fetched in check mode, so the checks have nothing to read.
Use `--syntax-check`, then a real run on a test VM. The role is safe to run again (the token service runs again each
time, which refreshes the token).

## Before the first run on a Grafana that is in use

What the role changes on the server, and what that does to a running Grafana:

| Change | Effect on a running Grafana |
| --- | --- |
| Installs `curl` and `jq` if missing, token script, token service and timer, token file in `/run` | None. The token is only read from the Azure metadata service and written to a file |
| The call to AWS STS (`ansible-check`) | None. It makes a session in AWS and a CloudTrail event, and changes nothing |
| Drop-in `aws-federation.conf` and the restart of Grafana | **Grafana restarts**: a few seconds of downtime, open sessions end, alert evaluation pauses |
| `datasources/datasources.yaml` (with `prune: true`) | **The one to look at first** (below) |

`datasources.yaml` is written after the token checks pass, and Grafana reads it at the restart. Before the first run:

1. `ls /etc/grafana/provisioning/datasources/` and read each file. A data source of the provisioning that is in no file
   of the role's list is deleted by `prune: true`. A data source of another file with the same name or uid as one in
   `datasources.yaml.j2` makes Grafana report a provisioning error. Merge them into one file, or turn off the other.
2. The `prometheus_uid` and `azure_monitor_uid` must be the uids that exist (`curl -u admin:<pw> <grafana url>/api/datasources`).
   A new uid makes a second data source, the dashboards still point to the old one, and prune deletes it.
3. Copy `/etc/grafana` somewhere safe (`sudo cp -a /etc/grafana /root/grafana-backup`).

To test the token and the AWS trust with **no change at all** to the server, do not run the role: use the commands of
*Claims of a token* above, then call STS by hand (needs only `curl`):

```bash
curl -s -X POST "https://sts.<region>.amazonaws.com/" -H "Accept: application/json" \
  --data-urlencode "Action=AssumeRoleWithWebIdentity" --data-urlencode "Version=2011-06-15" \
  --data-urlencode "RoleArn=<aws_role_arn>" --data-urlencode "RoleSessionName=manual-check" \
  --data-urlencode "DurationSeconds=900" --data-urlencode "WebIdentityToken=$TOKEN" \
  | jq 'if .Error or .ErrorResponse then . else "OK: AWS accepted the token" end'
```

`OK` here means the Azure side, the OIDC provider and the role trust all work. The answer holds credentials, so the
`jq` line prints only the verdict.

## Check on the server

```bash
systemctl list-timers grafana-aws-token.timer           # next run
journalctl -u grafana-aws-token.service -n 20           # token errors (Azure side)
ls -l /run/aws-web-identity/                            # token: root:grafana, 0640
sudo systemctl show grafana-server -p Environment       # the three AWS_* variables
sudo tr '\0' '\n' < /proc/$(systemctl show -p MainPID --value grafana-server)/environ | grep AWS_   # what the process has
journalctl -u grafana-server --since "5 min ago" | grep -i -E "aws|cloudwatch|error"
```

In AWS, CloudTrail shows `AssumeRoleWithWebIdentity` with `RoleSessionName` `ansible-check` (the role's own check) and
the sessions of Grafana's SDK after that.

## When it stops

| Message of the role | Cause |
| --- | --- |
| The token service failed | Managed Identity not attached, `azure_mi_client_id` is the object ID instead of the client ID, `AADSTS500011` (audience) |
| The token is not what the AWS trust expects | `aud`, `iss` or `sub` differs from `azure_audience`, `azure_mi_object_id` and the AWS stack. Change the variable or the stack, then apply again |
| AWS STS refused the token, `InvalidIdentityToken` | The OIDC provider of the stack does not match `iss` or `aud` of the token (v1 or v2 issuer, the last `/`) |
| AWS STS refused the token, `AccessDenied` | The trust of the role has another `aud` or `sub`, or `aws_role_arn` is wrong |
| AWS STS refused the token, no answer | The VM cannot reach `sts.<region>.amazonaws.com:443` |
| Save & test: `no EC2 IMDS role found` | The `AWS_*` variables are not in the Grafana process: check the drop-in and that Grafana was restarted |

`grafana.ini` is not touched by this role. A Grafana that has not limited `[aws] allowed_auth_providers` already allows
`default`. If your `grafana.ini` limits it, the list must include `default`, and must keep `keys` or `credentials` if
another data source uses an access key: removing them would break that data source.

A CloudWatch data source that exists already with the uid `cloudwatch_uid` (created by hand, or by the Terraform stack
`environment/grafana-datasources`) must have one owner. This role provisions the same uid with `prune: true`: if the
stack also creates it, turn one of the two off.

## Not verified

Nothing was run on a server, and `ansible-playbook --syntax-check` and `ansible-lint` were not run on the last
changes (the claims check, the STS check and `meta/main.yml`): run both before the first use. Open points, the first
three the same as in terraform-pipeline-test `environment/grafana-datasources/README.md`:

- Whether the Azure metadata service issues a token for the audience `api://aws-sts` of a Managed Identity (whether
  the Entra app registration is needed), and how AWS handles the `sts.windows.net` issuer of v1 tokens.
- That Grafana, on an Azure VM, picks up `AWS_WEB_IDENTITY_TOKEN_FILE` through AWS SDK Default.
- `RuntimeDirectory` with `User=root` and `Group=grafana` gives a directory `root:grafana 0750` (systemd behavior as
  documented); check it with `ls -ld /run/aws-web-identity` after the first run.
- That the AWS STS Query API answers JSON to `Accept: application/json` when called without a signature. The role
  only reads the HTTP status of the answer, so a different answer format does not matter; a status other than 200 stops it.
- The decoding of the token payload in Jinja (`b64decode` of the base64url part with padding added).

Try it on a test VM first. If the token step fails, `journalctl -u grafana-aws-token.service` shows the answer of the
metadata service.
