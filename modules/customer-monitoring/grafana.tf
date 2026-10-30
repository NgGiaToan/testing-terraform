# DISABLED (the Grafana role is not used): every customer is in the same account as the monitoring, and Grafana reads
# that account with the federation role of environment/shr-grafana-federation, so no role is needed per customer.
# Remove the /* and */ lines (and the same in variables.tf, outputs.tf and the environments) to switch it back on.
/*
# Read-only access for the internal Grafana. Grafana has one CloudWatch data source per
# customer account, each assuming this role (`Assume Role ARN`). The role grants CloudWatch
# read permissions only — no write, no other services — and its trust policy allows only the
# Grafana account.

locals {
  grafana_enabled = var.grafana_account_id != null
}

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

data "aws_iam_policy_document" "grafana_read" {
  count = local.grafana_enabled ? 1 : 0

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

  # Grafana's CloudWatch data source also discovers instances/regions by tag.
  statement {
    sid       = "ResourceDiscoveryRead"
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances", "ec2:DescribeRegions", "tag:GetResources"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "grafana_read" {
  count              = local.grafana_enabled ? 1 : 0
  name               = "${local.name_prefix}-grafana-read"
  assume_role_policy = data.aws_iam_policy_document.grafana_trust[0].json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "grafana_read" {
  count  = local.grafana_enabled ? 1 : 0
  name   = "${local.name_prefix}-grafana-read"
  role   = aws_iam_role.grafana_read[0].id
  policy = data.aws_iam_policy_document.grafana_read[0].json
}
*/
