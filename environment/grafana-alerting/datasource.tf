# The folder of the alert rules. The CloudWatch data sources (management account and customers) are
# created by environment/grafana-datasources, which has to be applied first: the rules read the
# management data source by its uid (var.management_data_source_uid).
resource "grafana_folder" "lighthouse" {
  title = "Lighthouse alerting"
  uid   = "lighthouse-alerting"
}
