###############################################################################
# Shared base infrastructure: VPC, ECS Cluster, SQS, ECR, Task Definition, IAM
###############################################################################
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}


locals {
  required_tags = {
    Name      = "${var.env}-worker"
    Team      = "devops"
    Component = "backend-graphql"
  }
}

data "aws_caller_identity" "current" {}

# ──────────────────────────────────────────────── VPC & Networking

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.required_tags, var.tags, { Name = "${var.env}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.required_tags, var.tags, { Name = "${var.env}-igw" })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zones[0]
  map_public_ip_on_launch = true
  tags                    = merge(local.required_tags, var.tags, { Name = "${var.env}-public" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.required_tags, var.tags, { Name = "${var.env}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(local.required_tags, var.tags, { Name = "${var.env}-nat" })
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]
  tags              = merge(local.required_tags, var.tags, { Name = "${var.env}-private-${count.index}" })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.env}-ecs-worker-"
  description = "ECS worker tasks"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-ecs-worker-sg" })
}

# ──────────────────────────────────────────────── ECS Cluster

resource "aws_ecs_cluster" "main" {
  name = "${var.env}-worker-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-worker-cluster" })
}

# ──────────────────────────────────────────────── SQS Queue (work queue)

resource "aws_sqs_queue" "work_dlq" {
  name                      = "${var.env}-worker-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = merge(local.required_tags, var.tags, { Name = "${var.env}-worker-dlq" })
}

resource "aws_sqs_queue" "work" {
  name                       = "${var.env}-worker-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.work_dlq.arn
    maxReceiveCount     = 3
  })

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-worker-queue" })
}

# ──────────────────────────────────────────────── ECR Repository

resource "aws_ecr_repository" "worker" {
  name                 = "${var.env}-worker"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-worker-ecr" })
}

# ──────────────────────────────────────────────── IAM

resource "aws_iam_role" "ecs_execution" {
  name = "${var.env}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-ecs-execution-role" })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_logs" {
  name = "${var.env}-ecs-execution-logs"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup"]
      Resource = ["arn:aws:logs:${var.region}:${data.aws_caller_identity.current.account_id}:*"]
    }]
  })
}

resource "aws_iam_role" "ecs_task" {
  name = "${var.env}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-ecs-task-role" })
}

resource "aws_iam_role_policy" "ecs_task_sqs" {
  name = "${var.env}-ecs-task-sqs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      Resource = [aws_sqs_queue.work.arn]
    }]
  })
}

# ──────────────────────────────────────────────── ECS Task Definition

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.env}-worker-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "worker"
    image     = var.container_image
    cpu       = 0
    essential = true

    environment = [
      { name = "ENV", value = var.env },
      { name = "QUEUE_URL", value = aws_sqs_queue.work.url },
      { name = "AWS_REGION", value = var.region }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-create-group"  = "true"
        "awslogs-group"         = "/ecs/${var.env}-worker-task"
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = merge(local.required_tags, var.tags, { Name = "${var.env}-worker-task" })
}
