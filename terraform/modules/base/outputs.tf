output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "security_group_id" {
  value = aws_security_group.ecs.id
}

output "ecs_cluster_id" {
  value = aws_ecs_cluster.main.id
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "sqs_queue_name" {
  value = aws_sqs_queue.work.name
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.work.arn
}

output "task_definition_family" {
  value = aws_ecs_task_definition.worker.family
}

output "ecr_repository_url" {
  value = aws_ecr_repository.worker.repository_url
}

output "required_tags" {
  value = local.required_tags
}
