output "function_name" {
  description = "Updater Lambda function name; invoke it to run the updater outside its schedule."
  value       = aws_lambda_function.this.function_name
}

output "age_alarm_name" {
  description = "Alarm that fires when a running instance's AMI is over 21 days old."
  value       = aws_cloudwatch_metric_alarm.age.alarm_name
}
