###############################################################################
# Root config — wires base infra + both scaling examples
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

# ──────────────────────────────────────────────── Shared base infrastructure

module "base" {
  source = "./modules/base"
  env    = var.env
  region = var.region
}

# ──────────────────────────────────────────────── Example 1: Step Scaling

module "step_scaling" {
  source = "./modules/step-scaling"

  env                    = var.env
  region                 = var.region
  ecs_cluster_name       = module.base.ecs_cluster_name
  task_definition_family = module.base.task_definition_family
  private_subnet_ids     = module.base.private_subnet_ids
  security_group_id      = module.base.security_group_id
  sqs_queue_name         = module.base.sqs_queue_name
  max_tasks              = 10
}

# ──────────────────────────────────────────────── Example 2: Target Tracking

module "target_tracking" {
  source = "./modules/target-tracking"

  env                     = var.env
  region                  = var.region
  ecs_cluster_name        = module.base.ecs_cluster_name
  task_definition_family  = module.base.task_definition_family
  private_subnet_ids      = module.base.private_subnet_ids
  security_group_id       = module.base.security_group_id
  sqs_queue_name          = module.base.sqs_queue_name
  max_tasks               = 10
  target_backlog_per_task = 5
}
