###############################################################################
# Step Scaling — scale ECS tasks 1:1 with SQS queue depth, scale to zero
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
  service_name = "${var.env}-worker-step"
  required_tags = {
    Name      = local.service_name
    Team      = "devops"
    Component = "backend-graphql"
  }
}

# ──────────────────────────────────────────────── ECS Service (desired_count = 0)

resource "aws_ecs_service" "worker" {
  name            = local.service_name
  cluster         = var.ecs_cluster_name
  task_definition = var.task_definition_family
  desired_count   = 0
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  lifecycle {
    ignore_changes = [desired_count]
  }

  tags = merge(local.required_tags, var.tags)
}

# ──────────────────────────────────────────────── Autoscaling Target

resource "aws_appautoscaling_target" "ecs" {
  resource_id        = "service/${var.ecs_cluster_name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  min_capacity       = 0
  max_capacity       = var.max_tasks
}

# ──────────────────────────────────────────────── Scale-Up Policy (1 message = 1 task)

resource "aws_appautoscaling_policy" "scale_up" {
  name               = "${local.service_name}-scale-up"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = "ExactCapacity"
    cooldown                = var.scale_up_cooldown
    metric_aggregation_type = "Maximum"

    # Generate one step per message count: 1 msg → 1 task, 2 → 2, … , (max-1) → (max-1)
    dynamic "step_adjustment" {
      for_each = range(1, var.max_tasks)
      content {
        metric_interval_lower_bound = step_adjustment.value - 1
        metric_interval_upper_bound = step_adjustment.value
        scaling_adjustment          = step_adjustment.value
      }
    }

    # max+ messages → max tasks
    step_adjustment {
      metric_interval_lower_bound = var.max_tasks - 1
      scaling_adjustment          = var.max_tasks
    }
  }
}

# ──────────────────────────────────────────────── Scale-Up Alarm (total messages >= 1)

resource "aws_cloudwatch_metric_alarm" "scale_up" {
  alarm_name          = "${local.service_name}-scale-up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Scale ECS tasks to match total SQS messages (step scaling)"

  metric_query {
    id          = "total"
    expression  = "visible + in_flight"
    label       = "TotalMessages"
    return_data = true
  }

  metric_query {
    id          = "visible"
    return_data = false
    metric {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions  = { QueueName = var.sqs_queue_name }
    }
  }

  metric_query {
    id          = "in_flight"
    return_data = false
    metric {
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions  = { QueueName = var.sqs_queue_name }
    }
  }

  alarm_actions = [aws_appautoscaling_policy.scale_up.arn]
  tags          = merge(local.required_tags, var.tags, { Name = "${local.service_name}-scale-up-alarm" })
}

# ──────────────────────────────────────────────── Scale-Down-to-Zero Policy

resource "aws_appautoscaling_policy" "scale_down" {
  name               = "${local.service_name}-scale-down-zero"
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  step_scaling_policy_configuration {
    adjustment_type = "ExactCapacity"
    cooldown        = var.scale_down_cooldown

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = 0
    }
  }
}

# ──────────────────────────────────────────────── Scale-Down Alarm (total messages = 0)

resource "aws_cloudwatch_metric_alarm" "scale_down" {
  alarm_name          = "${local.service_name}-scale-down-zero"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 0
  alarm_description   = "Scale to zero when SQS queue is empty"

  metric_query {
    id          = "total"
    expression  = "visible + in_flight"
    label       = "TotalMessages"
    return_data = true
  }

  metric_query {
    id          = "visible"
    return_data = false
    metric {
      metric_name = "ApproximateNumberOfMessagesVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions  = { QueueName = var.sqs_queue_name }
    }
  }

  metric_query {
    id          = "in_flight"
    return_data = false
    metric {
      metric_name = "ApproximateNumberOfMessagesNotVisible"
      namespace   = "AWS/SQS"
      period      = 60
      stat        = "Sum"
      dimensions  = { QueueName = var.sqs_queue_name }
    }
  }

  alarm_actions = [aws_appautoscaling_policy.scale_down.arn]
  tags          = merge(local.required_tags, var.tags, { Name = "${local.service_name}-scale-down-alarm" })
}
