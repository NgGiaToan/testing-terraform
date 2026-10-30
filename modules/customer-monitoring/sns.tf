# Where the alarms send their notifications.
#
# This account has no SNS topics of its own. Every alarm publishes to the priority topic
# (alerts-p1/p2/p3) of its environment in the management account, in the same region as the alarm,
# next to that environment's alert delivery Lambda (modules/alert-delivery). The topic's policy there
# takes alarms from any account, as long as the alarm is named <customer>-<priority>-<key> (the P1
# topic takes *-P1-*), so adding a customer needs no change on the management side.
#
# The topic ARN is built from fixed names, so there is nothing to copy from an output:
#   arn:aws:sns:<region>:<management_account_id>:<alert_topic_name_prefix>-<alert environment>-<region>-alerts-<p1|p2|p3>
# The management account must have these topics in this region for this environment: run
# environment/shr-monitoring with environment=<alert environment> and this region, once.

locals {
  priorities = toset(["P1", "P2", "P3"])

  # The environment the alerts belong to, derived from var.environment (the one name this module
  # is given), so the two cannot disagree: the standard environments map to dev, stg and prd, and
  # any other environment keeps its full name. This is the `environment` of the shr-monitoring
  # deployment whose Lambda, topics and Slack channels receive these alarms.
  #   dev-cus0001 -> dev     staging-demo -> stg     prod-cus0001 -> prd     demo-foo -> demo-foo
  alert_environment = (
    can(regex("^dev(-|$)", var.environment)) ? "dev" :
    can(regex("^(stg|staging)(-|$)", var.environment)) ? "stg" :
    can(regex("^(prd|prod)(-|$)", var.environment)) ? "prd" :
    var.environment
  )

  # Explicit ARNs win. Otherwise they are built from management_account_id; with neither set
  # there are no topics, and the alarms are created without notification actions.
  central_alert_topic_arns = var.central_alert_topic_arns != null ? var.central_alert_topic_arns : (
    var.management_account_id == null ? tomap({}) : tomap({
      for p in local.priorities :
      p => "arn:aws:sns:${var.region}:${var.management_account_id}:${var.alert_topic_name_prefix}-${local.alert_environment}-${var.region}-alerts-${lower(p)}"
    })
  )
}

# The alert environment is part of the topic names, and a shr-monitoring deployment's `environment`
# is 1-13 characters of lowercase letters, digits and hyphens. A name outside that can have no
# deployment, so the alarms would point at topics that cannot exist and fail to notify without any
# error here. This fails the plan instead. It cannot check that the deployment exists: run
# environment/shr-monitoring for this environment and region first.
resource "terraform_data" "alert_environment_check" {
  lifecycle {
    precondition {
      condition     = var.central_alert_topic_arns != null || var.management_account_id == null || can(regex("^[a-z0-9]([a-z0-9-]{0,11}[a-z0-9])?$", local.alert_environment))
      error_message = "The alert environment \"${local.alert_environment}\" (from environment \"${var.environment}\") cannot be a shr-monitoring deployment: it must be 1-13 characters, lowercase letters, digits and hyphens, not starting or ending with a hyphen. Use a shorter environment name, or set central_alert_topic_arns."
    }
  }
}
