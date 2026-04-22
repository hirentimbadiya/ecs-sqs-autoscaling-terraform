variable "env" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet (NAT gateway)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "AZs for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "container_image" {
  description = "Container image URI for the worker task"
  type        = string
  default     = "amazon/amazon-ecs-sample"
}

variable "task_cpu" {
  description = "CPU units for the Fargate task"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "Memory (MiB) for the Fargate task"
  type        = number
  default     = 1024
}

variable "tags" {
  description = "Additional tags to merge"
  type        = map(string)
  default     = {}
}
