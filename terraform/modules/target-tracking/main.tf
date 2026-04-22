###############################################################################
# Target Tracking — maintain a target backlog-per-task from SQS
###############################################################################

locals {
  service_name = "${var.env}-worker-target"
  required_tags = {
    Name      = local.service_name
    Team      = "devops"
    Component = "backend-graphql"
  }
}

# ──────────────────────────────────────────────── ECS Service

resource "aws_ecs_service" "worker" {
  name            = local.service_name
  cluster         = var.ecs_cluster_name
  task_definition = var.task_definition_family
  desired_count   = var.min_tasks
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
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

# ──────────────────────────────────────────────── Target Tracking Policy (custom metric)
#
# The idea: publish a custom metric = visible_messages / running_tasks.
# Target Tracking keeps that ratio at var.target_backlog_per_task.
# AWS manages both scale-out and scale-in automatically.

resource "aws_appautoscaling_policy" "target_tracking" {
  name               = "${local.service_name}-target-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = var.target_backlog_per_task
    scale_in_cooldown  = var.scale_in_cooldown
    scale_out_cooldown = var.scale_out_cooldown

    customized_metric_specification {
      metrics {
        id          = "backlog_per_task"
        expression  = "visible / running"
        label       = "BacklogPerTask"
        return_data = true
      }

      metrics {
        id = "visible"
        metric_stat {
          metric {
            metric_name = "ApproximateNumberOfMessagesVisible"
            namespace   = "AWS/SQS"
            dimensions {
              name  = "QueueName"
              value = var.sqs_queue_name
            }
          }
          stat = "Average"
        }
        return_data = false
      }

      metrics {
        id = "running"
        metric_stat {
          metric {
            metric_name = "RunningTaskCount"
            namespace   = "ECS/ContainerInsights"
            dimensions {
              name  = "ClusterName"
              value = var.ecs_cluster_name
            }
            dimensions {
              name  = "ServiceName"
              value = local.service_name
            }
          }
          stat = "Average"
        }
        return_data = false
      }
    }
  }
}
