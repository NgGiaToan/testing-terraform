# Read-only access for the internal Grafana to the management account. Serves the panels that
# are not per customer (Network Firewall, quota usage, Lambda formatter): Grafana has one
# extra CloudWatch data source for this account that assumes this role. Same shape as the
# per-customer role in modules/customer-monitoring/grafana.tf — CloudWatch read only, trust
# limited to the Grafana account with an external ID.

locals {
  grafana_enabled = var.grafana_account_id != null && nonsensitive(var.grafana_external_id != null)
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
    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.grafana_external_id]
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

  statement {
    sid       = "ResourceDiscoveryRead"
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions", "tag:GetResources"]
    resources = ["*"]
  }
}

# IAM roles are global, so the region is in the name: one instance of this module per region
# can share the management account.
resource "aws_iam_role" "grafana_read" {
  count              = local.grafana_enabled ? 1 : 0
  name               = "${local.name_prefix}-${var.region}-grafana-read"
  assume_role_policy = data.aws_iam_policy_document.grafana_trust[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "grafana_read" {
  count  = local.grafana_enabled ? 1 : 0
  name   = "${local.name_prefix}-${var.region}-grafana-read"
  role   = aws_iam_role.grafana_read[0].id
  policy = data.aws_iam_policy_document.grafana_read[0].json
}
