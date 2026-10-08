terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Account-wide security/capacity alerting (GuardDuty, Security Hub, Access Analyzer,
  # service quotas) — same convention as shr-iam/shr-backup-dr: account-level, rarely
  # changes, applied manually by an admin, not from CI.
  backend "s3" {
    bucket       = "testing-terraform-tfstate"
    key          = "shr-security-alerts/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}

# Real values pending Phase 0 sign-off (Slack channel, bot token secret) — see
# modules/account-security-alerts/README.md.
variable "slack_bot_token_secret_arn" {
  description = "Secrets Manager secret ARN holding the Slack bot token. Null skips Slack delivery until it's provisioned."
  type        = string
  default     = null
}

variable "slack_channel" {
  description = "Slack channel for account-level security/capacity alerts. Placeholder pending the real channel name."
  type        = string
  default     = "platform-ops-security"
}

module "account_security_alerts" {
  source = "../../modules/account-security-alerts"

  slack_bot_token_secret_arn = var.slack_bot_token_secret_arn
  slack_channel              = var.slack_channel
}
