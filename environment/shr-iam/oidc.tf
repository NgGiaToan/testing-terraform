# GitHub Actions <-> AWS OIDC setup: the identity provider AWS trusts, the IAM roles a
# CI/CD job assumes via `aws-actions/configure-aws-credentials` (role-to-assume) after
# requesting an OIDC token with `permissions: id-token: write`, and the attachment of each
# role to its policy (defined in github_actions.tf). main.tf only holds the
# backend/provider/data-source boilerplate that isn't specific to the GitHub OIDC setup —
# see OIDC-FLOW.md for the full request/response sequence.
#
# Exactly two roles exist:
#   - github_actions_non_prod: plans every environment, and applies/destroys TempStaging.
#   - github_actions_apply: applies every other environment (staging, prod, ...), gated to
#     pushes on main.

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

# Trust condition for the non-prod role. The wildcard "repo:ORG/REPO:*" is safe here
# because the attached policy (non_prod_access) is mostly read-only, plus a
# resource-scoped write carve-out for TempStaging alone — see OIDC-FLOW.md.
data "aws_iam_policy_document" "github_actions_non_prod_assume" {
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

# Non-prod role: plans every environment, plus a TempStaging-scoped write carve-out (see
# non_prod_access's TempStaging* statements in github_actions.tf) so apply-tempstaging/
# destroy-tempstaging in infrastructure-pr.yml can reuse this same role instead of the
# main-only apply role. Trust condition (github_actions_non_prod_assume, above) is
# intentionally the broad "repo:ORG/REPO:*" — every plan job in this repo (whether
# triggered by `pull_request` or `push` to main) also declares `environment:`, which makes
# GitHub emit an environment-scoped `sub` regardless of trigger, so a narrower literal
# match on `pull_request`/`ref:refs/heads/main` would never match anything real. Because
# the trust condition is this broad, EVERY plan-* job across EVERY environment can assume
# this role — the TempStaging write carve-out is therefore live for all of them, not just
# plan-tempstaging; it's scoped as tightly as AWS's resource ARNs allow (see
# github_actions.tf) to limit the blast radius of that. See OIDC-FLOW.md.
resource "aws_iam_role" "github_actions_non_prod" {
  name               = "github-actions-non-prod"
  assume_role_policy = data.aws_iam_policy_document.github_actions_non_prod_assume.json
}

resource "aws_iam_role_policy_attachment" "non_prod_access" {
  role       = aws_iam_role.github_actions_non_prod.name
  policy_arn = aws_iam_policy.non_prod_access.arn
}

# Trust condition for the write-tier (apply) role only — narrower than
# github_actions_non_prod_assume on purpose, and strictly main-branch-only. TempStaging
# used to be a deliberate PR-triggered exception here, but apply-tempstaging/
# destroy-tempstaging (infrastructure-pr.yml) assume the non-prod role instead — see the
# TempStaging carve-out statements on non_prod_access in github_actions.tf — so this role
# doesn't need (or allow) a PR-time path at all. See OIDC-FLOW.md's "Apply role" section.
data "aws_iam_policy_document" "github_actions_apply_assume" {
  statement {
    sid     = "ApplyFromMainPushOnly"
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
      values   = ["repo:NgGiaToan/testing-terraform:environment:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:ref"
      values   = ["refs/heads/main"]
    }
  }
}

# Apply role: read-write for every environment except TempStaging. Assumed by every
# `apply-*`/`destroy-*` job that runs on a push to main (apply-staging-demo,
# apply-staging-global, apply-prod-customers, apply-prod-global, ...) — one shared role
# since they never run concurrently against the same state and each is scoped to its own
# tfstate key. `apply-tempstaging`/`destroy-tempstaging` (infrastructure-pr.yml) do NOT use
# this role — TempStaging is PR-triggered, and this role's trust policy requires
# `ref = refs/heads/main` unconditionally, so a PR-triggered run can never assume it, full
# stop. TempStaging's apply/destroy instead reuses `github_actions_non_prod`.
resource "aws_iam_role" "github_actions_apply" {
  name               = "github-actions-apply"
  assume_role_policy = data.aws_iam_policy_document.github_actions_apply_assume.json
}

resource "aws_iam_role_policy_attachment" "apply_access" {
  role       = aws_iam_role.github_actions_apply.name
  policy_arn = aws_iam_policy.apply_access.arn
}

resource "aws_iam_role_policy_attachment" "monitoring_module" {
  role       = aws_iam_role.github_actions_apply.name
  policy_arn = aws_iam_policy.monitoring_module.arn
}

# The environment-scoped part, one policy per tier (dev, stg, prd). This role applies every
# environment, so it gets all three; a role limited to one tier would get only its own.
resource "aws_iam_role_policy_attachment" "monitoring_module_env" {
  for_each = aws_iam_policy.monitoring_module_env

  role       = aws_iam_role.github_actions_apply.name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy_attachment" "synthetics_canaries_module" {
  role       = aws_iam_role.github_actions_apply.name
  policy_arn = aws_iam_policy.synthetics_canaries_module.arn
}

# ARNs a CI/CD workflow needs for `role-to-assume` in aws-actions/configure-aws-credentials.
# The non-prod role is currently referenced in the workflows as a literal
# "arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/github-actions-non-prod" — these outputs
# exist so the ARN can be read with `terraform output` instead of hand-assembled.
output "github_actions_non_prod_role_arn" {
  value = aws_iam_role.github_actions_non_prod.arn
}

output "github_actions_apply_role_arn" {
  value = aws_iam_role.github_actions_apply.arn
}
