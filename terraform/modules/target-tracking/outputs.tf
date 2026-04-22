output "ecs_service_name" {
  value = aws_ecs_service.worker.name
}

output "target_tracking_policy_arn" {
  value = aws_appautoscaling_policy.target_tracking.arn
}
