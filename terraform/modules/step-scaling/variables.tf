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

variable "max_tasks" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 10
}

variable "scale_up_cooldown" {
  description = "Cooldown (seconds) after a scale-up action"
  type        = number
  default     = 30
}

variable "scale_down_cooldown" {
  description = "Cooldown (seconds) after a scale-down action"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
