variable "env" {
  description = "Environment name"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "task_definition_family" {
  description = "ECS task definition family"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ECS service"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for the ECS service"
  type        = string
}

variable "sqs_queue_name" {
  description = "SQS queue name to scale from"
  type        = string
}

variable "min_tasks" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "max_tasks" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 10
}

variable "target_backlog_per_task" {
  description = "Target SQS messages per ECS task (backlog-per-instance)"
  type        = number
  default     = 5
}

variable "scale_in_cooldown" {
  description = "Cooldown (seconds) before allowing another scale-in"
  type        = number
  default     = 120
}

variable "scale_out_cooldown" {
  description = "Cooldown (seconds) before allowing another scale-out"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
