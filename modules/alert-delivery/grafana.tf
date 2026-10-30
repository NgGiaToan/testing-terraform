# Grafana's access to AWS is NOT in this module any more. The federation role that Grafana's Azure VM assumes
# (OIDC provider + role, read-only, one for the whole account) lives in its own stack: environment/shr-grafana-federation.
# It was there because IAM is global: a role created from a per-environment, per-region deployment had to be turned
# on in ONE of them only.
#
# What is left in this file is DISABLED (commented out): two other ways in that are not used. A role that a Grafana
# server with its own AWS identity would assume (grafana_account_id), and an IAM user with an access key made by hand
# (grafana_user_enabled). They need the read-only policy below, which is why it is commented out with them.

# DISABLED (the Grafana role is not used): the data source reads through the role of environment/shr-grafana-federation.
/*
data "aws_iam_policy_document" "grafana_trust" {
  count = local.grafana_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.grafana_account_id}:root"]
    }
  }
}
*/

# DISABLED (the policy is in environment/shr-grafana-federation; the commented role and user below need it).
/*
data "aws_iam_policy_document" "grafana_read" {
  count = local.grafana_read_enabled ? 1 : 0

  statement {
    sid    = "CloudWatchRead"
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarms",
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetMetricStatistics",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetInsightRuleReport",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ResourceDiscoveryRead"
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions", "tag:GetResources"]
    resources = ["*"]
  }

  # Grafana's "Save & test" on a CloudWatch data source also lists log groups, and reports an error when it
  # cannot. Log groups are listed only, no log is read.
  statement {
    sid       = "DataSourceTestLogsList"
    effect    = "Allow"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"]
  }
}
*/

# IAM roles are global, so the region is in the name: one instance of this module per region
# can share the management account.
# DISABLED (the Grafana role is not used): the data source reads through the role of environment/shr-grafana-federation.
/*
resource "aws_iam_role" "grafana_read" {
  count              = local.grafana_enabled ? 1 : 0
  name               = "${local.shared_prefix}-${var.region}-grafana-read"
  assume_role_policy = data.aws_iam_policy_document.grafana_trust[0].json
  tags               = local.tags
}
*/

# DISABLED (the Grafana role is not used): see above.
/*
resource "aws_iam_role_policy" "grafana_read" {
  count  = local.grafana_enabled ? 1 : 0
  name   = "${local.shared_prefix}-${var.region}-grafana-read"
  role   = aws_iam_role.grafana_read[0].id
  policy = data.aws_iam_policy_document.grafana_read[0].json
}
*/

# DISABLED (the IAM user is not used): Grafana gets temporary credentials through federation, see environment/shr-grafana-federation.
/*
# ONE IAM user for Grafana in the whole account: IAM users are global and this one can read every region and
# every environment, so its name has no region and no environment. Turn grafana_user_enabled on in ONE
# deployment only (any region or environment): a second deployment with it on fails on the duplicate name.
# Its other permission, publishing the heartbeat (heartbeat.tf, switched off for now), is added to this same
# user. No access key here: see the header.
resource "aws_iam_user" "grafana_read" {
  count = var.grafana_user_enabled ? 1 : 0
  name  = "${local.shared_prefix}-grafana"
  tags  = local.tags
}

resource "aws_iam_user_policy" "grafana_read" {
  count  = var.grafana_user_enabled ? 1 : 0
  name   = "${local.shared_prefix}-grafana-read"
  user   = aws_iam_user.grafana_read[0].name
  policy = data.aws_iam_policy_document.grafana_read[0].json
}
*/
