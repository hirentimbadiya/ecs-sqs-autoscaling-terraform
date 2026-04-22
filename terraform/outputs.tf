output "sqs_queue_name" {
  value       = module.base.sqs_queue_name
  description = "SQS queue name"
}

output "step_scaling_service" {
  value       = module.step_scaling.ecs_service_name
  description = "ECS service name for step scaling"
}

output "target_tracking_service" {
  value       = module.target_tracking.ecs_service_name
  description = "ECS service name for target tracking scaling"
}
