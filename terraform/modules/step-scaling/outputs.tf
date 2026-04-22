output "ecs_service_name" {
  value = aws_ecs_service.worker.name
}

output "scale_up_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.scale_up.arn
}

output "scale_down_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.scale_down.arn
}
