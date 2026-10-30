# alert-delivery

Management-account half of the alerting pipeline. **One deployment is one environment in one
region**: deploy it once for each environment (dev, stg, prd, or a full name) and region that hosts
customers. The alert topics are regional and each customer alarm publishes to the topic in its own
region; each environment has its own Lambda, role, webhook secret and topics, named
`lighthouse-alerting-<environment>-<region>-...` (written `<name>` below). Applied manually from
`environment/shr-monitoring`, one workspace per deployment named `<environment>-<region>`.

This module was called `alert-formatter`. The Lambda that formats and posts the alerts is one piece of it, next to the topics, the
topic and key policies and the alarms of the delivery path. `shr-monitoring` keeps the state of an existing
deployment with a `moved` block (`module.alert_formatter` to `module.alert_delivery`).

| Piece | Purpose |
| --- | --- |
| Formatter Lambda (`<name>-formatter`) | Receives alerts from the priority topics below, formats them and posts to Slack through Incoming Webhooks. Reads `notify` from the alarm's JSON description to pick the Operations and/or Engineering webhook. Budgets and Cost Anomaly messages (free text) are routed by topic name and go to Operations (`Operations_TEAMS` in `slack_formatter.py`). |
| Alert topics | `<name>-alerts-p1/p2/p3`, delivering to the Lambda. **The alarms of the customer environments wired to this deployment, and its own alarms, publish here.** |
| Topic policy | This account, plus CloudWatch alarms of **any AWS account** whose name fits the topic's priority (`*-P1-*` on the P1 topic...); `Subscribe` only for this Lambda. Adding a customer needs no change here. The name rule is not a security boundary, and it does not check the environment (see below). |
| Pipeline topic | `<name>-pipeline`, delivering to the same Lambda so its alarms reach Slack (Engineering). Carries the alarms that watch the Lambda itself. **Known limit:** if the Lambda is down, those alarms cannot reach Slack through it; a path independent of the Lambda is still to be added. |
| Network Firewall alarm | `shared-P3-<environment>-firewall-drops`: `DroppedPackets` summed over all AZs and both engines (explicit metric math, max 4 AZs), against an anomaly band. |
| Quota alarms | Always created, no Lambda. `shared-P3-<environment>-quota-80-*` and `shared-P2-<environment>-quota-95-*` alarm on the usage metric AWS publishes itself (`AWS/Usage` `ResourceCount`, dimensions in `var.quotas`), divided by `SERVICE_QUOTA()` when the entry has no `limit`, else by its fixed `limit`. Default: the four regional AWS WAF quotas (web ACLs 100, rule groups 100, IP sets 100, regex pattern sets 10, each as `limit`; WAF does not integrate with `SERVICE_QUOTA()`, so change `limit` when the quota is raised). **Only quotas with an `AWS/Usage` metric can be watched this way:** VPCs and Elastic IPs have none, and ALBs/NLBs are not confirmed (add them to `var.quotas` once CloudWatch > Metrics > Usage > By AWS Resource shows their dimensions). Every deployment creates them, so with several environments in one region each quota is alarmed once per environment, into that environment's channels. **Not verified:** that WAF's metric has only the `Resource` dimension, and that it exists in your account (it appears only when a web ACL exists); check with `aws cloudwatch list-metrics --namespace AWS/Usage` before the first apply. |
| Delivery alarms | `shared-P2-<environment>-lambda-errors`, `-lambda-throttles`, and `-sns-failures-p1/p2/p3` (delivery of the alert topics) → pipeline topic. |

## Setup

1. In Slack, create an app with **Incoming Webhooks** and add two webhooks, one for the Operations
   channel and one for the Engineering channel. Test each URL with a `curl`/`Invoke-RestMethod`
   POST.
2. Apply `environment/shr-monitoring` for each environment and region, one workspace each (select the
   right one yourself: the `workspace_guard` that refused any other is commented out for now):

   ```text
   terraform workspace new prd-us-east-1        # first time; later: terraform workspace select
   terraform apply -var environment=prd -var region=us-east-1
   ```

   Unless `slack_webhook_secret_arn` points at an existing secret, Terraform creates the **empty**
   secret `lighthouse-alerting-<environment>-<region>-slack-webhooks` in the Lambda's region, one
   per deployment. Every deployment also creates the quota alarms (see [Quota monitoring](#quota-monitoring)):
   with several environments in one region each quota is alarmed once per environment, into its own channels.
3. Set the secret's value with the CLI, never in Terraform, so the URL stays out of the state.
   The value is JSON with both teams; a missing or empty team makes the Lambda fail instead of
   posting to another channel. The secret name is the `slack_webhook_secret_arn` output:

   ```text
   aws secretsmanager put-secret-value --secret-id <slack_webhook_secret_arn output> --region <region> \
     --secret-string file://webhooks.json   # {"Operations": "https://hooks.slack.com/...", "Engineering": "..."}
   ```

   Delete `webhooks.json` afterwards. Until the value is set the Lambda fails on every alert and
   the `lambda-errors` alarm fires. That alarm goes to the pipeline topic, which delivers to the same
   Lambda, so it cannot reach Slack while the Lambda fails: look for the Lambda's errors in CloudWatch.
4. Give each customer environment `management_account_id` (the `management_account_id` output).
   It builds the topic ARNs itself, so there is nothing else to copy. It derives the environment
   from its own `environment` (`dev-*` is dev, `staging-*` stg, `prod-*` prd, any other name as
   it is) and the topics of **that** deployment in its region: that deployment must exist.
5. Nothing to do per customer on this side: the topic policy already takes alarms from any
   account, new ones included.
6. Test end to end: `aws cloudwatch set-alarm-state` on a customer alarm, expect a Slack
   message in the right channel, then set it back to `OK` for the recovery message.

## Quota monitoring

No Lambda measures quotas. AWS publishes a usage metric (`AWS/Usage` `ResourceCount`) for some quotas, and the
alarms and the Grafana panel read it. Only quotas that have such a metric can be watched.

| Quota | Watched? | Why |
| --- | --- | --- |
| AWS WAF regional: web ACLs (100), rule groups (100), IP sets (100), regex pattern sets (10) | Yes (default) | Documented `AWS/Usage` metric, dimension `Resource` only. Published only when at least one such resource exists. |
| ALBs and NLBs per region (50 each) | Not yet | The docs list Elastic Load Balancing as integrated but give no metric name or dimensions. Add them once step 1 shows them. |
| VPCs, Elastic IPs | No | AWS publishes no usage metric. Only a Lambda that counts them could (not built). |
| AWS WAF for CloudFront | No | Its metrics are in us-east-1; deploy there and add the `...CloudFront` values. |

Steps:

1. **Check the metric exists** in the account and region, before the first apply: CloudWatch > Metrics > Usage >
   By AWS Resource, or `aws cloudwatch list-metrics --namespace AWS/Usage --region <region>`. Each quota in
   `var.quotas` needs its row with exactly the dimensions you configure. Not verified: that WAF's metric has only
   `Resource`.
2. **Declare the quotas** in `var.quotas` ([variables.tf:54](variables.tf#L54)): one entry per quota, `dimensions`
   (the metric's dimensions) and optional `limit`. No `limit` divides by `SERVICE_QUOTA()` (only for services that
   integrate with Service Quotas, not WAF); a number divides by that fixed quota, so change it when the quota is
   raised. Thresholds: `quota_warning_percent` ([variables.tf:70](variables.tf#L70), 80) and
   `quota_critical_percent` ([variables.tf:76](variables.tf#L76), 95).
3. **Apply** `environment/shr-monitoring` as usual: there is no switch, every deployment creates two alarms per quota
   ([alarms.tf:77](alarms.tf#L77) `quota_warning`, [alarms.tf:111](alarms.tf#L111) `quota_critical`), named
   `shared-P3-<environment>-quota-80-<key>` and `shared-P2-<environment>-quota-95-<key>`. Priority, recipients
   (Operations and Engineering) and message are in [main.tf:36](main.tf#L36) (`quota-80`) and
   [main.tf:40](main.tf#L40) (`quota-95`). Missing data counts as OK. Several environments in one region each
   alarm the same quota into their own channels.
4. **Grafana panel** "Quota usage %" in
   [platform.json:88](../customer-monitoring/grafana-dashboards/platform.json#L88): one hidden query per quota
   (metric) and one expression (`<id> / <limit> * 100`). The limit is written in the panel too, so change it in both places when a quota
   is raised. The datasource role already allows `cloudwatch:GetMetricData` and `ListMetrics`
   ([federation.tf:65](../../environment/shr-grafana-federation/federation.tf#L65)).
5. **Verify after apply:** the alarm graph (CloudWatch) shows the percentage line, not empty or
   `INSUFFICIENT_DATA`; the Platform dashboard shows the lines; then `aws cloudwatch set-alarm-state` on a quota
   alarm for an end-to-end Slack test.

To add a quota: one entry in `var.quotas` and one query pair in the panel. **Risk:** a wrong dimension gives
no data and the alarm stays OK, so it never fires; step 5 catches it.

## Regions

Alarms publish to the topic **in their own region**, as in AWS's cross-account example (the
alarm and the topic in the same region). So each environment and region that hosts customers needs
its own deployment: its topics, its Lambda and its webhook secret. Every Slack message shows the
alarm's environment and region.

- **The separation between environments is by wiring, not enforced.** A customer environment
  publishes to the topics of its own environment, so its alerts reach only that environment's
  channels. But the topic policy takes alarms from any account by alarm name and does not check the
  environment, so an alarm wired to the wrong deployment, or from an unknown account, can still
  publish to another environment's topics.
- **A customer environment pointing at no deployment fails silently.** Its alarms get actions that
  point at topics that do not exist, and nothing fails at apply. The customer module only rejects a
  name that no deployment can have (more than 13 characters or invalid characters).

- **The topics are open to any AWS account.** Anyone who learns a topic ARN can send
  alerts to your Slack, and enough of them can use up the Lambda's concurrency (default 1000 per
  region) so real alerts are delayed. A private webhook URL does not prevent it: the messages enter
  through the topic, not through the URL. To close them, list the allowed accounts in the policy
  (`SourceAccount`), at the cost of a change per new customer.
- A deployment serves one region: `environment/shr-monitoring` takes `region` and `environment`
  as variables, so a second region or environment is another run of the same code in another
  workspace, not another module call.
- **Not verified:** that the alarm and the topic must be in the same region (the docs show them
  together but do not say it is required); and that the topic policy lets an alarm of another
  account publish as written. Test with a real alarm in a customer account before relying on it.
- The topics (alerts P1-P3, pipeline) are encrypted at rest with one
  customer-managed KMS key (`kms.tf`). Its policy lets CloudWatch alarms of any account in the region
  use it, so a new customer still needs no change on the management side. **Not verified:** the AWS
  docs show that statement for one account's alarms; allowing any account is this module's design. After
  applying, test with a real alarm in a customer account. A key policy that is too narrow stops that
  account's alerts silently (visible only in the alarm's history).
- A single Lambda per region is a single point of failure for that region's alerts. Failures of
  the Lambda itself raise the `lambda-errors` alarm, which publishes to the pipeline topic. That
  topic delivers to the same Lambda, so while the Lambda is down this alarm cannot reach Slack. To be
  handled later with a path that does not depend on the Lambda.
- The Secrets Manager secret (`slack_webhook_secret_arn`) lives in the Lambda's region only.

## Grafana

The IAM user with an access key (`grafana_user_enabled`, output `grafana_user_name`) is **commented out**: it was for a Grafana server with no AWS identity and stays as a fallback. Uncomment it in `grafana.tf`, `variables.tf` and `outputs.tf` (and in `environment/shr-monitoring`) to bring it back.

The Grafana server runs on an **Azure VM**, so there is no access key: the role that Grafana assumes (OIDC federation) is **not in this module**. It is its own stack, `environment/shr-grafana-federation` (account-level IAM, one for the whole account). Not run yet.

The Grafana role (`grafana_account_id`, `grafana_role_arn`) is **commented out**: it needs an AWS identity on the Grafana
server, which this Grafana does not have. Uncomment it in `grafana.tf`, `variables.tf` and `outputs.tf` (and in
`modules/customer-monitoring`) to bring it back.

### Grafana watching the pipeline

Grafana can alert to Slack when the Lambdas or the alert topics fail (rules in `environment/grafana-alerting`).
Customer alerts stay on CloudWatch, SNS and the Lambda. There is **no heartbeat** back to AWS: Grafana runs on an
Azure VM, so watching Grafana itself is out of scope here. Grafana Cloud cannot load provisioning files, so the
Grafana side is a Terraform stack that talks to its API; see its README for the order of work and what is not
verified.

## Slack message

`P1 CRITICAL · [prd] acme-P1-prd-https-canary` with Customer, Environment, Region, Service, Alert,
Condition, State, Time and a link to the Environment Overview dashboard; colour bar red / orange / yellow for P1 / P2 / P3
and green on recovery. A failed webhook post is raised so the Lambda `Errors` alarm fires (the webhook URL is never logged).
