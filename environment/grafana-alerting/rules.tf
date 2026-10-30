# The alert rules: one group that alerts to Slack when the Lambdas or topics of the alert pipeline fail.
#
# "Alert pipeline health": Grafana reads CloudWatch metrics of the management account and
# alerts when the CloudWatch -> SNS -> Lambda -> Slack path breaks. These replace the alarms
# that used to publish to a topic with no subscriber. They go to your existing Slack contact
# point, through a per-rule route (notification_settings), so the notification policy tree of
# the stack is NOT touched.
#
# Not verified against a live Grafana: see README.md.

locals {
  cw           = var.management_data_source_uid # created by environment/grafana-datasources
  environments = var.alert_environments         # one alert delivery Lambda and one set of alert topics per environment (modules/alert-delivery)

  # What Grafana watches. Every check alerts on a Sum above 0 in the last 10 minutes.
  pipeline_checks = merge(
    {
      for t in local.environments : "formatter-errors-${t}" => {
        title     = "Alert delivery Lambda (${t}): errors"
        summary   = "The Lambda that sends ${t} alerts to Slack returned an error. Alerts may not reach Slack."
        namespace = "AWS/Lambda"
        metric    = "Errors"
        dimension = { FunctionName = "${var.name_prefix}-${t}-${var.region}-formatter" }
      }
    },
    {
      for t in local.environments : "formatter-throttles-${t}" => {
        title     = "Alert delivery Lambda (${t}): throttled"
        summary   = "The Lambda that sends ${t} alerts to Slack was throttled. Alerts are delayed or dropped."
        namespace = "AWS/Lambda"
        metric    = "Throttles"
        dimension = { FunctionName = "${var.name_prefix}-${t}-${var.region}-formatter" }
      }
    },
    {
      for pair in setproduct(local.environments, ["p1", "p2", "p3"]) : "sns-failures-${pair[0]}-${pair[1]}" => {
        title     = "Alert topic ${pair[0]} ${upper(pair[1])}: delivery failures"
        summary   = "SNS could not deliver an alert from the ${pair[0]} ${upper(pair[1])} topic to its alert delivery Lambda."
        namespace = "AWS/SNS"
        metric    = "NumberOfNotificationsFailed"
        dimension = { TopicName = "${var.name_prefix}-${pair[0]}-${var.region}-alerts-${pair[1]}" }
      }
    },
  )
}

resource "grafana_rule_group" "pipeline_health" {
  name             = "Alert pipeline health"
  folder_uid       = grafana_folder.lighthouse.uid
  interval_seconds = 60

  dynamic "rule" {
    for_each = local.pipeline_checks

    content {
      name           = rule.value.title
      condition      = "C"
      for            = "0s"
      no_data_state  = "OK"       # no errors published means nothing went wrong
      exec_err_state = "Alerting" # if Grafana cannot read CloudWatch, that is worth knowing too

      labels = {
        team     = "engineering"
        severity = "P2"
        source   = "grafana"
      }
      annotations = {
        summary = rule.value.summary
      }

      notification_settings {
        contact_point = var.slack_contact_point_name
      }

      data {
        ref_id = "A"
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = local.cw
        model = jsonencode({
          refId            = "A"
          datasource       = { type = "cloudwatch", uid = local.cw }
          queryMode        = "Metrics"
          metricQueryType  = 0
          metricEditorMode = 0
          region           = var.region
          namespace        = rule.value.namespace
          metricName       = rule.value.metric
          dimensions       = rule.value.dimension
          statistic        = "Sum"
          period           = "300"
          matchExact       = true
          id               = "a"
        })
      }

      data {
        ref_id = "B"
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = "__expr__"
        model = jsonencode({
          refId      = "B"
          datasource = { type = "__expr__", uid = "__expr__" }
          type       = "reduce"
          expression = "A"
          reducer    = "max"
          settings   = { mode = "dropNN" }
        })
      }

      data {
        ref_id = "C"
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = "__expr__"
        model = jsonencode({
          refId      = "C"
          datasource = { type = "__expr__", uid = "__expr__" }
          type       = "threshold"
          expression = "B"
          conditions = [{ evaluator = { type = "gt", params = [0] } }]
        })
      }
    }
  }
}
