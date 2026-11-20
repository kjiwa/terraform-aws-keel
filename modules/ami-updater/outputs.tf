output "function_name" {
  description = "Updater Lambda function name; invoke it to run the updater outside its schedule."
  value       = aws_lambda_function.this.function_name
}

output "alarm_names" {
  description = "Alarms for a running AMI far past ami_max_age_days and for updater failures."
  value       = [aws_cloudwatch_metric_alarm.age.alarm_name, aws_cloudwatch_metric_alarm.errors.alarm_name]
}
