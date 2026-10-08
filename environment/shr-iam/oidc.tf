# GitHub Actions <-> AWS OIDC setup: the identity provider AWS trusts, the IAM roles a
# CI/CD job assumes via `aws-actions/configure-aws-credentials` (role-to-assume) after
# requesting an OIDC token with `permissions: id-token: write`, and the attachment of each
# role to its policy (defined in github_actions.tf). main.tf only holds the
# backend/provider/data-source boilerplate that isn't specific to the GitHub OIDC setup —
# see OIDC-FLOW.md for the full request/response sequence.

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# Merged into every role's policy document in github_actions.tf via
# source_policy_documents — kept here since it's a property of the OIDC-assumed identity
# itself (no role chaining once assumed), not a permission specific to any one role's job.
# This is what enforces "a job assumes exactly one role and can't pivot to another
# mid-run": Deny is explicit rather than just omitted, so it wins over any Allow that might
# get attached to a role later — see OIDC-FLOW.md's "One role per job, no re-assuming
# mid-run".
data "aws_iam_policy_document" "deny_role_chaining" {
  statement {
    sid       = "DenyRoleChaining"
    effect    = "Deny"
    actions   = ["sts:AssumeRole"]
    resources = ["*"]
  }
}

# Shared trust condition for every read-only-tier role (github_actions_default and
# github_actions_plan both use it) — the wildcard "repo:ORG/REPO:*" is safe here because
# every job that assumes one of these roles only gets read access. A write-tier role would
# need its own, narrower document instead of reusing this one.
data "aws_iam_policy_document" "github_actions_readonly_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:NgGiaToan/testing-terraform:*"]
    }
  }
}

# Sanity-check role: proves the OIDC trust relationship works end-to-end (assume + one
# real read-only API call) without granting anything Terraform's init/plan actually needs.
resource "aws_iam_role" "github_actions_default" {
  name               = "github-actions-default"
  assume_role_policy = data.aws_iam_policy_document.github_actions_readonly_assume.json
}

resource "aws_iam_role_policy_attachment" "default_readonly" {
  role       = aws_iam_role.github_actions_default.name
  policy_arn = aws_iam_policy.default_readonly.arn
}

# Read-only. Trust condition (github_actions_readonly_assume, above) is intentionally the
# broad "repo:ORG/REPO:*" — every plan job in this repo (whether triggered by
# `pull_request` or `push` to main) also declares `environment:`, which makes GitHub emit
# an environment-scoped `sub` regardless of trigger, so a narrower literal match on
# `pull_request`/`ref:refs/heads/main` would never match anything real. The wildcard is
# acceptable given the attached policy grants read access only — see OIDC-FLOW.md.
resource "aws_iam_role" "github_actions_plan" {
  name               = "github-actions-terraform-plan"
  assume_role_policy = data.aws_iam_policy_document.github_actions_readonly_assume.json
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.github_actions_plan.name
  policy_arn = aws_iam_policy.plan_readonly.arn
}

# ARNs a CI/CD workflow needs for `role-to-assume` in aws-actions/configure-aws-credentials.
# The plan role is currently referenced in the workflows as a literal
# "arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-terraform-plan" — these
# outputs exist so the ARN can be read with `terraform output` instead of hand-assembled.
output "github_actions_default_role_arn" {
  value = aws_iam_role.github_actions_default.arn
}

output "github_actions_plan_role_arn" {
  value = aws_iam_role.github_actions_plan.arn
}
