output "sqs_queue_name" {
  value = module.base.sqs_queue_name
}

output "step_scaling_service" {
  value = module.step_scaling.ecs_service_name
}

output "target_tracking_service" {
  value = module.target_tracking.ecs_service_name
}
