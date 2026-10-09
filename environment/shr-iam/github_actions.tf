# What each GitHub Actions role (defined in oidc.tf) is allowed to do once assumed. Kept
# separate from oidc.tf so the "who can assume + trust condition" concern stays apart from
# the "what they can do" concern. Both policy documents merge in deny_role_chaining from
# oidc.tf so neither role can pivot to another mid-run.

data "aws_iam_policy_document" "default_readonly" {
  # Merges in the DenyRoleChaining statement from oidc.tf.
  source_policy_documents = [data.aws_iam_policy_document.deny_role_chaining.json]

  statement {
    sid       = "VpcDescribeReadOnly"
    effect    = "Allow"
    actions   = ["ec2:DescribeVpcs"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "default_readonly" {
  name        = "github-actions-default-readonly"
  path        = "/"
  description = "Read-only sanity-check access for the GitHub Actions default role"
  policy      = data.aws_iam_policy_document.default_readonly.json
}

data "aws_iam_policy_document" "plan_readonly" {
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

  statement {
    sid       = "TflockAccess"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [data.aws_dynamodb_table.tflock.arn]
  }

  # Read-only: lets the "discover customers"/"discover Demo/Testing envs" jobs enumerate
  # /oglh/customers/<code> and /envs/stg_* to build their matrix, without this list ever
  # being checked into the repo as directories.
  statement {
    sid     = "DiscoverEnvsFromSsm"
    effect  = "Allow"
    actions = ["ssm:GetParametersByPath", "ssm:GetParameters", "ssm:GetParameter"]
    resources = [
      "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/oglh/customers/*",
      "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:parameter/envs/*"
    ]
  }
}

resource "aws_iam_policy" "plan_readonly" {
  name        = "terraform-plan-readonly"
  path        = "/"
  description = "Read-only access for the GitHub Actions terraform-plan role"
  policy      = data.aws_iam_policy_document.plan_readonly.json
}
