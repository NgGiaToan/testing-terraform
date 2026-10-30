# What each GitHub Actions role (defined in oidc.tf) is allowed to do once assumed. Kept
# separate from oidc.tf so the "who can assume + trust condition" concern stays apart from
# the "what they can do" concern. Both policy documents merge in deny_role_chaining from
# oidc.tf so neither role can pivot to another mid-run.

data "aws_iam_policy_document" "non_prod_access" {
  # Merges in the DenyRoleChaining statement from oidc.tf.
  source_policy_documents = [data.aws_iam_policy_document.deny_role_chaining.json]

  # Bucket-attribute reads only (ACL/versioning/lifecycle/tags/...) for refreshing every
  # env's `aws_s3_bucket.example` — object-level reads are intentionally left out here and
  # scoped to the tfstate bucket alone in the next statement, since these actions don't
  # need object access and "*" would otherwise let this role read objects out of every
  # bucket in the account.
  statement {
    sid    = "S3BucketAttributesAndEc2DescribeReadOnly"
    effect = "Allow"
    actions = [
      "s3:GetBucket*",
      "s3:GetLifecycleConfiguration",
      "s3:GetEncryptionConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketPolicyStatus",
      "s3:ListAllMyBuckets",
      "s3:GetAccelerateConfiguration",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }

  # Object-level read, scoped to the tfstate bucket only — this is what
  # `terraform init`/`plan` actually needs to read the current state file.
  statement {
    sid       = "TfstateObjectRead"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [data.aws_s3_bucket.tfstate.arn, "${data.aws_s3_bucket.tfstate.arn}/*"]
  }

  # Read-only: lets the "discover customers"/"discover Demo/Testing envs" jobs enumerate
  # the oglh/customers/<code> and oglh/stg/<name> secrets to build their matrix, without
  # this list ever being checked into the repo as directories. ListSecrets only returns
  # names (never secret values, which this role has no need to read), but it's an
  # account-level action in the Secrets Manager API — like S3's ListAllMyBuckets below —
  # so it can't be scoped to the oglh/* name prefix by resource ARN; the prefix filtering
  # happens client-side in the workflow instead (see infrastructure-pr.yml/
  # infrastructure-main.yml).
  statement {
    sid       = "DiscoverEnvsFromSecretsManager"
    effect    = "Allow"
    actions   = ["secretsmanager:ListSecrets"]
    resources = ["*"]
  }

  # Read-only refresh for the customer-monitoring module (modules/customer-monitoring) so
  # `terraform plan` can read current state for environments that call it, without this
  # role being able to change anything. Resource scoping mirrors the write side
  # (apply_access.monitoring_module in this same file) one-for-one, split into per-service
  # statements since a statement's `resources` list applies uniformly to every action in it.
  # No SNS, KMS or Lambda here: a customer account has no topics or functions of its own. Its
  # alarms publish to the topics of the management account (modules/alert-delivery), which is
  # authorised by that topic's policy, not by this role.
  statement {
    sid    = "MonitoringIamReadOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies"
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-monitoring-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ec2_role"
    ]
  }

  statement {
    sid       = "MonitoringCloudWatchAlarmsReadOnly"
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["arn:aws:cloudwatch:*:${data.aws_caller_identity.current.account_id}:alarm:*"]
  }

  # Anomaly detector models (network egress, VPN connections, WAF blocked requests) aren't
  # ARN-addressable — same "*" fallback as the Cost Anomaly Detection statement below.
  statement {
    sid       = "MonitoringAnomalyDetectionReadOnly"
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAnomalyDetectors"]
    resources = ["*"]
  }

  statement {
    sid       = "MonitoringSsmParameterReadOnly"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/*/cloudwatch-agent/config"]
  }

  statement {
    sid       = "MonitoringBudgetsReadOnly"
    effect    = "Allow"
    actions   = ["budgets:ViewBudget"] # AWS Budgets has one read action (ViewBudget) for every Describe* call
    resources = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/*-monthly-budget"]
  }

  # Cost Anomaly Detection doesn't support resource-level ARN scoping for these read
  # actions either — same "*" fallback as the write side.
  statement {
    sid       = "MonitoringAnomalyDetectionCostReadOnly"
    effect    = "Allow"
    actions   = ["ce:GetAnomalyMonitors", "ce:GetAnomalySubscriptions"]
    resources = ["*"]
  }

  # Read-only refresh for modules/synthetics-canaries, mirroring
  # synthetics_canaries_module's resource scoping below.
  statement {
    sid       = "CanaryArtifactsBucketReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetBucket*"]
    resources = ["arn:aws:s3:::*-canaries-artifacts-*"]
  }

  statement {
    sid       = "CanaryExecutionRoleReadOnly"
    effect    = "Allow"
    actions   = ["iam:GetRole", "iam:GetRolePolicy"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-canaries-execution"]
  }

  statement {
    sid     = "CanaryReadOnly"
    effect  = "Allow"
    actions = ["synthetics:GetCanary", "synthetics:ListTagsForResource"]
    resources = [
      "arn:aws:synthetics:*:${data.aws_caller_identity.current.account_id}:canary:*-https-availability",
      "arn:aws:synthetics:*:${data.aws_caller_identity.current.account_id}:canary:*-workflow"
    ]
  }

  # --- TempStaging apply/destroy carve-out --------------------------------------------
  # apply-tempstaging/destroy-tempstaging (infrastructure-pr.yml) assume this role instead
  # of github_actions_apply, since that role is main-branch-only. The statements below
  # grant just enough write access to apply/destroy TempStaging, scoped to its own
  # resources wherever an IAM resource ARN can express that. Because this role's trust
  # condition is the broad "repo:ORG/REPO:*" (see oidc.tf), every plan-* job in the repo
  # can assume it — so these statements have to be scoped narrowly by resource, not relied
  # on to be reached only by the TempStaging jobs.

  # Tfstate write, scoped to the tempstaging/* key prefix only (the backend key every
  # TempStaging job uses — infrastructure-pr.yml) — every other environment's state stays
  # read-only under this role.
  statement {
    sid       = "TempStagingTfstateWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${data.aws_s3_bucket.tfstate.arn}/tempstaging/*"]
  }

  # Full lifecycle for TempStaging's example bucket only. Its name is always
  # "my-example-test-bucket-12345-tempstaging-pr<number>" (environment/tempstaging/main.tf)
  # — a prefix no other environment's bucket name can match.
  statement {
    sid    = "TempStagingBucketManage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucket*",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutBucketAcl",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::my-example-test-bucket-12345-tempstaging-pr*",
      "arn:aws:s3:::my-example-test-bucket-12345-tempstaging-pr*/*"
    ]
  }

  # Full lifecycle for TempStaging's example security group. Unlike the bucket above, EC2
  # doesn't support resource-level ARN scoping for these actions (same limitation noted on
  # apply_access's ExampleSecurityGroupManage below) — this has to be "*", so unlike the
  # two statements above it is NOT actually scoped to TempStaging alone: any plan-* job for
  # any environment gains these actions account-wide. Accepted tradeoff of merging
  # plan+apply into one role for TempStaging.
  statement {
    sid    = "TempStagingSecurityGroupManage"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags",
      "ec2:DeleteTags"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "non_prod_access" {
  name        = "terraform-non-prod"
  path        = "/"
  description = "Read-only access for every environment, plus a TempStaging-scoped write carve-out, for the GitHub Actions non-prod role"
  policy      = data.aws_iam_policy_document.non_prod_access.json
}

# Read-write, for the apply role only. Every environment/*/main.tf in this repo currently
# creates the same two example resources (aws_s3_bucket + aws_security_group), all
# bucket-named "my-example-test-bucket-12345-<environment>" — this policy is scoped to that
# shared shape, not to any one environment directory, since the same role applies all of
# them.
data "aws_iam_policy_document" "apply_access" {
  # Merges in the DenyRoleChaining statement from oidc.tf.
  source_policy_documents = [data.aws_iam_policy_document.deny_role_chaining.json]

  # Object-level read/write on the tfstate bucket — what `terraform apply` needs to read
  # the current state and write the updated one back after applying.
  statement {
    sid       = "TfstateObjectReadWrite"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
    resources = [data.aws_s3_bucket.tfstate.arn, "${data.aws_s3_bucket.tfstate.arn}/*"]
  }

  # Full lifecycle (create/read/update/delete) for every environment's example bucket —
  # scoped to the shared "my-example-test-bucket-12345-*" name prefix rather than "*".
  statement {
    sid    = "ExampleBucketManage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucket*",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
      "s3:PutBucketAcl",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketOwnershipControls",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::my-example-test-bucket-12345-*",
      "arn:aws:s3:::my-example-test-bucket-12345-*/*"
    ]
  }

  # ListAllMyBuckets is account-level in the S3 API and can't be scoped to a resource ARN.
  statement {
    sid       = "S3AccountListReadOnly"
    effect    = "Allow"
    actions   = ["s3:ListAllMyBuckets"]
    resources = ["*"]
  }

  # Full lifecycle for every environment's example security group. EC2 doesn't support
  # resource-level ARN scoping for these actions, so this is "*" like the read-only
  # equivalents in non_prod_access above.
  statement {
    sid    = "ExampleSecurityGroupManage"
    effect = "Allow"
    actions = [
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSecurityGroupRules",
      "ec2:DescribeVpcs",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }
}

# Write access for the customer-monitoring module (modules/customer-monitoring), scoped
# by ARN/name pattern to that module's naming convention wherever the AWS API supports
# resource-level scoping. A few actions (Cost Anomaly Detection, anomaly detector models)
# fall back to "*" the same way ExampleSecurityGroupManage above does, because those APIs
# generate the resource ID at create time and don't support resource-level IAM scoping.
data "aws_iam_policy_document" "monitoring_module" {
  # No SNS, KMS or Lambda: since alarms publish straight to the management account's topics
  # (see sns.tf in the module), a customer account has none of its own, and publishing needs
  # no permission here: the topic policy in the management account lets the alarms in.
  # The management side (modules/alert-delivery: Lambda, topics, secrets, one stack per
  # environment and region) is applied by an admin from environment/shr-monitoring, not by this role.

  # What is scoped by environment (the Grafana read-only role and the CloudWatch agent SSM
  # parameter, both named after the environment) is in monitoring_module_env below, one policy
  # per environment. What follows cannot be: alarms, budgets and Cost Anomaly Detection are
  # named after the customer or generated by AWS, not after the environment.

  # ec2_role is pre-existing (created outside Terraform, already attached to monitored
  # instances) — this module only attaches the managed CloudWatchAgentServerPolicy to it,
  # scoped to that specific role name since it doesn't follow the "<environment>-monitoring-*"
  # naming convention.
  statement {
    sid    = "MonitoringExistingEc2RoleAttach"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/ec2_role"]
  }

  statement {
    sid    = "MonitoringCloudWatchAlarms"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:TagResource"
    ]
    resources = ["arn:aws:cloudwatch:*:${data.aws_caller_identity.current.account_id}:alarm:*"]
  }

  # Anomaly detector models (network egress, VPN connections, WAF blocked requests) aren't
  # ARN-addressable, so this falls back to "*" like Cost Anomaly Detection below.
  statement {
    sid    = "MonitoringAnomalyDetection"
    effect = "Allow"
    actions = [
      "cloudwatch:PutAnomalyDetector",
      "cloudwatch:DeleteAnomalyDetector",
      "cloudwatch:DescribeAnomalyDetectors"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "MonitoringBudgets"
    effect = "Allow"
    # AWS Budgets has two actions on a budget: ModifyBudget (create, update and delete) and
    # ViewBudget (every Describe* call). There is no CreateBudget or DeleteBudget action.
    actions = [
      "budgets:ModifyBudget",
      "budgets:ViewBudget"
    ]
    resources = ["arn:aws:budgets::${data.aws_caller_identity.current.account_id}:budget/*-monthly-budget"]
  }

  # Cost Anomaly Detection monitor/subscription ARNs are also generated at create time and
  # this API doesn't support resource-level scoping by name.
  statement {
    sid    = "MonitoringCostAnomalyDetection"
    effect = "Allow"
    actions = [
      "ce:CreateAnomalyMonitor",
      "ce:CreateAnomalySubscription",
      "ce:DeleteAnomalyMonitor",
      "ce:DeleteAnomalySubscription",
      "ce:UpdateAnomalyMonitor",
      "ce:UpdateAnomalySubscription",
      "ce:GetAnomalyMonitors",
      "ce:GetAnomalySubscriptions",
      "ce:TagResource"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "monitoring_module" {
  name        = "terraform-monitoring-module"
  path        = "/"
  description = "Write access for the customer-monitoring module that is not scoped by environment (alarms, budgets, Cost Anomaly Detection, ec2_role), for the GitHub Actions apply role"
  policy      = data.aws_iam_policy_document.monitoring_module.json
}

locals {
  # Environment tier => the prefix the environments of that tier name themselves with: the
  # `environment` of dev-cus0001 is "dev-cus0001", of stg-customer "staging-<env_name>" and of
  # prd-customer "prod-<customer_code>". The module names its resources after it.
  # An environment named any other way (customer-monitoring then alerts under its full name)
  # matches none of these: add its prefix here, or the apply role cannot create its Grafana
  # role and agent parameter.
  monitoring_environments = {
    dev = "dev-*"
    stg = "staging-*"
    prd = "prod-*"
  }
}

# The part of the customer-monitoring write access that CAN be scoped by environment: the
# Grafana read-only role ("<environment>-monitoring-grafana-read") and the CloudWatch agent
# config parameter ("/<environment>/cloudwatch-agent/config"). One policy per tier, so a role
# for a single tier can be given just its own. Today the apply role is one role for every
# environment, so it gets all three and this narrows nothing yet; it is the split a per-tier
# apply role needs.
data "aws_iam_policy_document" "monitoring_module_env" {
  for_each = local.monitoring_environments

  statement {
    sid    = "MonitoringIamRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${each.value}-monitoring-*"]
  }

  statement {
    sid    = "MonitoringSsmParameter"
    effect = "Allow"
    actions = [
      "ssm:PutParameter",
      "ssm:GetParameter",
      "ssm:DeleteParameter",
      "ssm:AddTagsToResource"
    ]
    resources = ["arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/${each.value}/cloudwatch-agent/config"]
  }
}

resource "aws_iam_policy" "monitoring_module_env" {
  for_each = local.monitoring_environments

  name        = "terraform-monitoring-module-${each.key}"
  path        = "/"
  description = "Write access for the customer-monitoring module that is scoped to the ${each.key} environments (Grafana read-only role, CloudWatch agent parameter), for the GitHub Actions apply role"
  policy      = data.aws_iam_policy_document.monitoring_module_env[each.key].json
  tags        = { Tier = each.key }
}

# Write access for modules/synthetics-canaries, scoped by ARN/name pattern to that
# module's naming convention ("<environment>-canaries-*" / "<customer_code>-https-
# availability" / "<customer_code>-workflow").
data "aws_iam_policy_document" "synthetics_canaries_module" {
  statement {
    sid    = "CanaryArtifactsBucketManage"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucket*",
      "s3:PutBucketTagging",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::*-canaries-artifacts-*",
      "arn:aws:s3:::*-canaries-artifacts-*/*"
    ]
  }

  statement {
    sid    = "CanaryExecutionRoleManage"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:TagRole",
      "iam:UntagRole"
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-canaries-execution"]
  }

  # Canaries run as Lambda functions under the hood, so the execution role is passed to
  # lambda.amazonaws.com.
  statement {
    sid       = "CanaryExecutionRolePassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/*-canaries-execution"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }

  statement {
    sid    = "CanaryManage"
    effect = "Allow"
    actions = [
      "synthetics:CreateCanary",
      "synthetics:DeleteCanary",
      "synthetics:GetCanary",
      "synthetics:UpdateCanary",
      "synthetics:StartCanary",
      "synthetics:StopCanary",
      "synthetics:TagResource",
      "synthetics:ListTagsForResource"
    ]
    resources = [
      "arn:aws:synthetics:*:${data.aws_caller_identity.current.account_id}:canary:*-https-availability",
      "arn:aws:synthetics:*:${data.aws_caller_identity.current.account_id}:canary:*-workflow"
    ]
  }
}

resource "aws_iam_policy" "synthetics_canaries_module" {
  name        = "terraform-synthetics-canaries-module"
  path        = "/"
  description = "Write access for the synthetics-canaries module, for the GitHub Actions apply role"
  policy      = data.aws_iam_policy_document.synthetics_canaries_module.json
}

resource "aws_iam_policy" "apply_access" {
  name        = "terraform-apply"
  path        = "/"
  description = "Read-write access for the GitHub Actions apply role"
  policy      = data.aws_iam_policy_document.apply_access.json
}
