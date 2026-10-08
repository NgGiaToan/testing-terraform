# alert-formatter

Management-account half of the alerting pipeline. Deploy **once per region** that hosts
customers (SNS can only deliver to a Lambda in its own region); applied manually from
`environment/shr-monitoring`.

| Piece | Purpose |
| --- | --- |
| Formatter Lambda (`lighthouse-alerting-formatter`) | Receives alerts from every customer account's `alerts-p1/p2/p3` topics, formats them and posts to Slack with `chat.postMessage`. Reads `notify` from the alarm's JSON description to pick the Operations and/or Engineering channel. Budgets and Cost Anomaly messages (free text) are routed by topic name and go to Operations. |
| Lambda resource policy | One statement per ID in `customer_account_ids`, limited to that account's `*-monitoring-alerts-p*` topics. **Add the account here when onboarding a customer.** |
| Management priority topics | `lighthouse-alerting-alerts-p1/p2/p3`, KMS-encrypted, delivering to the same Lambda. Carry this account's own alarms. |
| Pipeline topic | Email to Engineering. Carries the alarms that watch the Lambda itself, so a broken formatter cannot silence them. |
| Network Firewall alarm | `P3-firewall-drops`: `DroppedPackets` summed over all AZs and both engines (explicit metric math, max 4 AZs), against an anomaly band. |
| Quota publisher + alarms | Every 5 minutes publishes `Lighthouse/Quotas` `QuotaUsagePercent` for VPCs and Elastic IPs; `P3-quota-80-*` and `P2-quota-95-*` alarm on it. |
| Delivery alarms | `P2-lambda-errors`, `P2-lambda-throttles`, `P2-quota-job-errors` → pipeline topic. |

## Setup

1. Create the Slack app, give it `chat:write`, invite it to both channels, and store the
   `xoxb-` token in a Secrets Manager secret in the management account.
2. Apply `environment/shr-monitoring` with `slack_bot_token_secret_arn`, the channel names and
   `engineering_alert_emails` (confirm the SNS email subscriptions).
3. Copy `formatter_lambda_arn` and `management_account_id` into each customer environment.
4. Add each customer account ID to `customer_account_ids` and re-apply **before** the customer
   environment is applied — the customer's topic subscribes to the Lambda and needs the
   permission to exist.
5. Test end to end: `aws cloudwatch set-alarm-state` on a customer alarm, expect a Slack
   message in the right channel, then set it back to `OK` for the recovery message.

## Slack message

`P1 CRITICAL · acme-P1-https-canary` with Customer, Service, Alert, Condition, State, Time and a
link to the Environment Overview dashboard; colour bar red / orange / yellow for P1 / P2 / P3
and green on recovery. A Slack API error is raised so the Lambda `Errors` alarm fires.
