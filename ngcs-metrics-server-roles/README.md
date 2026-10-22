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
role lighthouse-alerting-grafana-federated  ──►  CloudWatch of the management account (sink) ──► customer accounts
```

The data source itself says only `authType: default`. The link with the OIDC setup is these environment variables
of the service: the AWS SDK sees them and does the exchange. The AWS side (OIDC provider, role, read-only policy)
is the stack `environment/shr-grafana-federation` of terraform-pipeline-test; the sink and the links are
`environment/shr-monitoring` and the customer environments.

What the role puts on the server:

| Path | What |
| --- | --- |
| `/usr/local/bin/grafana-aws-token.sh` | Asks Azure for the token, writes a temp file and renames it |
| `/etc/systemd/system/grafana-aws-token.service` and `.timer` | Runs the script at boot (1 min) and every `aws_token_refresh` |
| `/etc/systemd/system/grafana-server.service.d/aws-federation.conf` | The three AWS variables, and `Wants/After` the token service so a token exists before Grafana starts |
| `/etc/grafana/provisioning/datasources/datasources.yaml` | The data sources |

After the changes the role runs the token service once, restarts Grafana, and stops if the token file is missing,
empty or not readable by the Grafana group.

## Values passed in from outside

The role has no real values inside it. These must be passed in, and the role stops at the first task with a
clear message if one is missing:

| Variable | Meaning |
| --- | --- |
| `prometheus_url`, `prometheus_version`, `prometheus_uid` | Prometheus data source |
| `azure_subscription_id`, `azure_monitor_uid` | Azure Monitor data source |
| `cloudwatch_default_region` | Region of the sink (needed when `cloudwatch_enabled`) |
| `aws_role_arn` | Output `grafana_federated_role_arn` of `shr-grafana-federation` (needed when `aws_federation_enabled`) |
| `azure_mi_client_id` | Client ID of the Managed Identity of the VM (needed when `aws_federation_enabled`) |
| `azure_audience` | Audience of the token, same as `grafana_azure_audience` in the AWS stack (needed when `aws_federation_enabled`) |
| `grafana_admin_password` | To reload Grafana; Ansible Vault or the environment |

Optional, with a default in [config/defaults/main.yml](config/defaults/main.yml): `cloudwatch_enabled`,
`cloudwatch_uid`, `cloudwatch_assume_role_arn`, `aws_federation_enabled`, `aws_region`, `aws_token_file`,
`aws_token_refresh`, `grafana_url`, `grafana_admin_user`, `grafana_service_name`, `grafana_group`,
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

## Use

```yaml
- hosts: grafana
  become: true
  roles:
    - role: config
```

Then open the CloudWatch data source in Grafana and press **Save & test**.

## Check on the server

```bash
systemctl list-timers grafana-aws-token.timer           # next run
journalctl -u grafana-aws-token.service -n 20           # token errors (Azure side)
sudo systemctl show grafana-server -p Environment       # the three AWS_* variables
```

## Not verified

Nothing was run on a server. The templates and YAML were only parsed and rendered with a Jinja-compatible engine.
Open points, the same as in terraform-pipeline-test `environment/grafana-datasources/README.md`:

- Whether the Azure metadata service issues a token for the audience `api://aws-sts` of a Managed Identity (whether
  the Entra app registration is needed), and how AWS handles the `sts.windows.net` issuer of v1 tokens.
- That Grafana, on an Azure VM, picks up `AWS_WEB_IDENTITY_TOKEN_FILE` through AWS SDK Default.
- `RuntimeDirectory` with `User=root` and `Group=grafana` gives a directory `root:grafana 0750` (systemd behavior as
  documented); check it with `ls -ld /run/aws-web-identity` after the first run.

Try it on a test VM first. If the token step fails, `journalctl -u grafana-aws-token.service` shows the answer of the
metadata service.
