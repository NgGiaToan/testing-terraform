# account-security-alerts

Account-wide security/capacity alerting: GuardDuty, Security Hub, IAM Access Analyzer, and
service quotas. Apply this **once per account**, not once per customer — these findings
have no Customer/Environment tag to scope by, unlike `modules/customer-monitoring`.

## Usage

```hcl
module "account_security_alerts" {
  source = "../../modules/account-security-alerts"

  slack_bot_token_secret_arn = var.slack_bot_token_secret_arn
  slack_channel              = "platform-ops-security"
}
```

- **GuardDuty/Security Hub/Access Analyzer** arrive via EventBridge rules → this module's
  SNS topic → the Slack Lambda. Security Hub and Access Analyzer need to already be
  enabled in this account/region — the EventBridge rules match on their event shape but
  don't turn the services on.
- **Service quotas** (`service_quota_checks`) are plain CloudWatch alarms on the
  `AWS/Usage` namespace, which only populates once "Monitor with CloudWatch" is turned on
  per quota in the Service Quotas console — Terraform has no resource to flip that toggle.
  Confirm the real dimensions via `aws cloudwatch list-metrics --namespace AWS/Usage`
  before trusting the defaults in the variable description.

## Known simplifications

- GuardDuty severity buckets (High/Medium) are split via EventBridge's numeric matcher, not
  by a Lambda re-deriving severity — keeps the Lambda simple, but the exact bucket
  boundary lives in two places (the EventBridge pattern and the Lambda's own >=7/>=4
  fallback labeling for defense in depth).
- Security Hub's `Workflow.Status = NEW` filter avoids re-alerting on every re-scan of an
  existing finding, per the monitoring spec's own note about this.
