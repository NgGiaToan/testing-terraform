# alert-formatter

Management-account half of the alerting pipeline. Deploy **once per region** that hosts
customers (SNS can only deliver to a Lambda in its own region); applied manually from
`environment/shr-monitoring`.

| Piece | Purpose |
| --- | --- |
| Formatter Lambda (`lighthouse-alerting-formatter`) | Receives alerts from every customer account's `alerts-p1/p2/p3` topics, formats them and posts to Slack through Incoming Webhooks. Reads `notify` from the alarm's JSON description to pick the Operations and/or Engineering webhook. Budgets and Cost Anomaly messages (free text) are routed by topic name and go to Operations. |
| Lambda resource policy | One statement per ID in `customer_account_ids`, limited to that account's `*-monitoring-alerts-p*` topics. **Add the account here when onboarding a customer.** |
| Management priority topics | `lighthouse-alerting-alerts-p1/p2/p3`, KMS-encrypted, delivering to the same Lambda. Carry this account's own alarms. |
| Pipeline topic | Email to Engineering. Carries the alarms that watch the Lambda itself, so a broken formatter cannot silence them. |
| Network Firewall alarm | `P3-firewall-drops`: `DroppedPackets` summed over all AZs and both engines (explicit metric math, max 4 AZs), against an anomaly band. |
| Quota publisher + alarms | Every 5 minutes publishes `Lighthouse/Quotas` `QuotaUsagePercent` for VPCs and Elastic IPs; `P3-quota-80-*` and `P2-quota-95-*` alarm on it. |
| Delivery alarms | `P2-lambda-errors`, `P2-lambda-throttles`, `P2-quota-job-errors` → pipeline topic. |

## Setup

1. In Slack, create an app with **Incoming Webhooks** and add one webhook per channel (or a single
   one if every alert goes to one channel). Test each URL with a `curl`/`Invoke-RestMethod` POST.
2. Apply `environment/shr-monitoring` (set `engineering_alert_emails` and confirm the SNS email
   subscriptions). Unless `slack_webhook_secret_arn` points at an existing secret, Terraform
   creates the **empty** secret `lighthouse-alerting-slack-webhooks` in the Lambda's region.
3. Set the secret's value with the CLI, never in Terraform, so the URL stays out of the state.
   One URL for all teams, or JSON per team (a team missing from the JSON falls back to
   Operations). The secret name is the `slack_webhook_secret_arn` output:

   ```text
   aws secretsmanager put-secret-value --secret-id <slack_webhook_secret_arn output> --region <region> \
     --secret-string file://webhooks.json   # {"Operations": "https://hooks.slack.com/...", "Engineering": "..."}
   ```

   Delete `webhooks.json` afterwards. Until the value is set the Lambda fails on every alert and
   the `lambda-errors` alarm emails Engineering.
4. Copy `formatter_lambda_arn` and `management_account_id` into each customer environment.
5. Add each customer account ID to `customer_account_ids` and re-apply **before** the customer
   environment is applied — the customer's topic subscribes to the Lambda and needs the
   permission to exist.
6. Test end to end: `aws cloudwatch set-alarm-state` on a customer alarm, expect a Slack
   message in the right channel, then set it back to `OK` for the recovery message.

## Regions

The Lambda is deployed in `region` (default `ap-southeast-2`, Sydney) and one instance can serve
customers in several regions: list the other regions in `customer_regions`. Each customer
account in `customer_account_ids` is then allowed to invoke it from each of those regions, and
every Slack message shows the alarm's region.

- The customer's topic subscribes to the Lambda ARN **from the topic's own account and region**
  (the AWS CLI command must run there). `modules/customer-monitoring` does this when it gets
  `formatter_lambda_arn`.
- Regions enabled by default (launched before 2019-03-20, e.g. `us-east-1`, `ap-southeast-2`,
  `eu-west-1`) need nothing more. For a topic in an opt-in region (e.g. `ap-east-1`,
  `me-south-1`, `eu-south-1`) the module sets the principal to `sns.<region>.amazonaws.com`.
- AWS's own docs disagree on delivery to Lambda **from a default-enabled region to an opt-in
  region and between two opt-in regions** ([prerequisites page](https://docs.aws.amazon.com/sns/latest/dg/lambda-prereq.html)
  says unsupported, [cross-region page](https://docs.aws.amazon.com/sns/latest/dg/sns-cross-region-delivery.html)
  says supported). Test those with a real alarm before relying on them.
- A single Lambda is a single point of failure for every region's alerts. Failures of the
  Lambda itself still go out by email through the pipeline topic.
- The Secrets Manager secret (`slack_webhook_secret_arn`) lives in the Lambda's region only.

## Grafana

Set `grafana_account_id` and `grafana_external_id` to create a read-only role in the management
account (CloudWatch read only, trust limited to the Grafana account with the external ID). Enter
the `grafana_role_arn` output as the `Assume Role ARN` of Grafana's management-account CloudWatch
data source. It serves the Network Firewall, quota and Lambda panels of the dashboards in
`modules/customer-monitoring/grafana-dashboards`. The role name includes the region, so one
instance per region can share the account.

## Slack message

`P1 CRITICAL · acme-P1-https-canary` with Customer, Service, Alert, Condition, State, Time and a
link to the Environment Overview dashboard; colour bar red / orange / yellow for P1 / P2 / P3
and green on recovery. A failed webhook post is raised so the Lambda `Errors` alarm fires (the webhook URL is never logged).
