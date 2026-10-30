# Read-only access for the internal Grafana to this AWS account, which holds both the monitoring and every
# customer's resources: the CloudWatch metrics of all of them (Network Firewall, quota, Lambda, SNS, and each
# customer's instances, load balancers, canaries).
#
# No key at all: the Grafana server runs on an Azure VM, whose Managed Identity can prove who it is to AWS (OIDC
# federation). AWS trusts Microsoft Entra ID as an identity provider and lets that one identity assume this
# read-only role (AssumeRoleWithWebIdentity), so the VM gets temporary credentials and nothing long-lived is stored.

locals {
  tags = { ManagedBy = "terraform", Component = "grafana-federation" }

  # The Entra issuer of a Managed Identity token (v1 tokens), and the prefix of the condition keys of the trust.
  # Not verified: the condition keys with this prefix (sts.windows.net/<tenant>/:aud and :sub).
  azure_issuer = "sts.windows.net/${var.grafana_azure_tenant_id}/"
}

# Tells AWS to trust tokens that Microsoft Entra ID issues for this tenant and audience.
# One provider per issuer URL and account: a second apply with the same URL elsewhere fails on the duplicate.
resource "aws_iam_openid_connect_provider" "azure" {
  url            = "https://${local.azure_issuer}"
  client_id_list = [var.grafana_azure_audience]
  tags           = local.tags
}

# The role accepts one subject only: the Managed Identity of the Grafana VM.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.azure.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.azure_issuer}:aud"
      values   = [var.grafana_azure_audience]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.azure_issuer}:sub"
      values   = [var.grafana_azure_subject]
    }
  }
}

# One role for the whole account (IAM is global): no region and no environment in the name.
resource "aws_iam_role" "grafana" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "read" {
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

  # The dashboards pick a customer by its tags (Customer, Environment): tag:GetResources lists resources by tag,
  # ec2:DescribeInstances lets the EC2 instance variables read the instances and their tags.
  statement {
    sid       = "ResourceDiscoveryRead"
    effect    = "Allow"
    actions   = ["ec2:DescribeRegions", "ec2:DescribeInstances", "tag:GetResources"]
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

resource "aws_iam_role_policy" "read" {
  name   = "grafana-read"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.read.json
}
