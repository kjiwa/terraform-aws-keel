# Cost Anomaly Detection: a per-service monitor on spend deviating from baseline.
#
# Both Budgets and Anomaly Detection read billing data that trails actual
# usage by 8-24h, so neither catches a runaway while it is still happening.
resource "aws_ce_anomaly_monitor" "service" {
  name              = "${var.name_prefix}-service-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name             = "${var.name_prefix}-anomalies"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.service.arn]

  subscriber {
    type    = "EMAIL"
    address = var.alert_email
  }

  # Only surface anomalies whose absolute cost impact is at least $5, so
  # rounding noise on a small bill does not email daily.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["5"]
    }
  }
}
