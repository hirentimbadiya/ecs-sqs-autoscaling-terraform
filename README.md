# ecs-sqs-autoscaling-terraform

> Production-ready Terraform modules for ECS Fargate autoscaling driven by SQS queue depth — covering both **Step Scaling** and **Target Tracking** approaches with a scale-from-zero pattern.

[![Terraform CI](https://github.com/hirentimbadiya/ecs-sqs-autoscaling-terraform/actions/workflows/ci.yml/badge.svg)](https://github.com/hirentimbadiya/ecs-sqs-autoscaling-terraform/actions/workflows/ci.yml)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS_Provider-~%3E5.0-FF9900?logo=amazonaws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

---

## Why This Repo?

Scaling ECS tasks from an SQS queue is a common pattern, but AWS gives you two very different mechanisms to do it. Most tutorials cover one or the other. This repo provides **both side-by-side** with production-ready Terraform so you can compare, learn, and deploy.

---

## Scaling Approaches

### Step Scaling (Deterministic)

Maps SQS queue depth 1:1 to ECS task count using dynamic step adjustments.

- 1 message → 1 task, 2 messages → 2 tasks, …, N+ → max tasks
- Scales to **zero** when the queue is empty
- Uses CloudWatch Alarms with metric math (`visible + in_flight`)
- You control every step — fully transparent

### Target Tracking (Adaptive)

Maintains a target **backlog-per-task** ratio. AWS manages the scaling automatically.

- Custom metric: `ApproximateNumberOfMessagesVisible / RunningTaskCount`
- AWS creates and manages alarms internally
- Requires **ECS Container Insights** enabled (included in the base module)
- Minimum capacity ≥ 1 (cannot scale to zero natively)

### Comparison

| Aspect | Step Scaling | Target Tracking |
|---|---|---|
| Scale to zero | ✅ Native | ❌ Needs hybrid |
| Config complexity | Higher (dynamic steps + 2 alarms) | Lower (1 policy) |
| Reaction speed | Fast (60s alarm) | Moderate (AWS-managed) |
| Predictability | Deterministic | Adaptive |
| Dependencies | None | Container Insights |
| Best for | Bursty, short-lived jobs | Steady throughput |

---

## Project Structure

```
.
├── README.md
├── LICENSE
├── .github/
│   └── workflows/
│       └── ci.yml                       # Terraform fmt, validate, tflint, checkov
└── terraform/
    ├── main.tf                          # Root config — wires all modules
    ├── variables.tf
    ├── outputs.tf
    ├── example.tfvars                   # Example variable values
    ├── .tflint.hcl                      # TFLint config with AWS ruleset
    └── modules/
        ├── base/                        # Shared infra
        │   ├── main.tf                  #   VPC, public + private subnets, IGW, NAT gateway,
        │   ├── variables.tf             #   route tables, SG, ECS cluster (Container Insights),
        │   └── outputs.tf              #   SQS + DLQ, ECR, IAM roles + policies, task def
        ├── step-scaling/                # Step Scaling approach
        │   ├── main.tf                  #   ECS service, scale-up policy (dynamic steps),
        │   ├── variables.tf             #   scale-down-to-zero policy, CloudWatch alarms
        │   └── outputs.tf
        └── target-tracking/             # Target Tracking approach
            ├── main.tf                  #   ECS service, target tracking policy
            ├── variables.tf             #   with custom backlog-per-task metric
            └── outputs.tf
```

---

## Prerequisites

1. **Terraform** >= 1.5 — [Install guide](https://developer.hashicorp.com/terraform/install)
2. **AWS account** — a fresh account works fine
3. **AWS CLI** configured with credentials that have admin access (or at minimum: VPC, ECS, SQS, ECR, IAM, CloudWatch, Application Auto Scaling, Elastic IP permissions)

   ```bash
   # Option A: configure a profile
   aws configure --profile demo
   export AWS_PROFILE=demo

   # Option B: export credentials directly
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_REGION="us-east-1"
   ```

4. **Verify access:**
   ```bash
   aws sts get-caller-identity
   ```

5. *(Optional)* [TFLint](https://github.com/terraform-linters/tflint) for local linting
6. *(Optional)* [Checkov](https://www.checkov.io/) for local security scanning

---

## Step-by-Step Deployment

### 1. Clone the repo

```bash
git clone https://github.com/hirentimbadiya/ecs-sqs-autoscaling-terraform.git
cd ecs-sqs-autoscaling-terraform/terraform
```

### 2. Review and set variables

```bash
# Copy the example file
cp example.tfvars terraform.tfvars

# Edit if needed (defaults work out of the box)
# env    = "demo"
# region = "us-east-1"
```

All variables have sensible defaults. You can deploy without changing anything.

### 3. Initialize Terraform

```bash
terraform init
```

This downloads the AWS provider and initializes the modules. State is stored locally (no remote backend configured — add your own S3 backend for production use).

### 4. Preview the plan

```bash
terraform plan
```

You should see ~30 resources to create:
- VPC, subnets, internet gateway, NAT gateway, route tables, elastic IP
- Security group
- ECS cluster (with Container Insights)
- SQS queue + dead-letter queue
- ECR repository
- IAM roles and policies (execution role, task role)
- ECS task definition
- 2 ECS services (one for step scaling, one for target tracking)
- Autoscaling targets, policies, and CloudWatch alarms

### 5. Apply

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes ~3–5 minutes (NAT gateway creation is the slowest part).

### 6. Test the scaling

Send messages to the SQS queue to trigger autoscaling:

```bash
# Get the queue URL
QUEUE_URL=$(aws sqs get-queue-url \
  --queue-name demo-worker-queue \
  --query 'QueueUrl' --output text)

# Send 5 test messages
for i in $(seq 1 5); do
  aws sqs send-message \
    --queue-url "$QUEUE_URL" \
    --message-body "{\"job_id\": $i, \"payload\": \"test\"}"
done

# Watch the step-scaling service react (check after ~2 minutes)
aws ecs describe-services \
  --cluster demo-worker-cluster \
  --services demo-worker-step \
  --query 'services[0].{desired:desiredCount,running:runningCount}'
```

> **Note:** The default container image (`amazon/amazon-ecs-sample`) is a sample nginx image — it doesn't actually consume SQS messages. Tasks will start and run, demonstrating the scaling behavior, but won't drain the queue. For a real workload, replace `container_image` with your own SQS-consuming worker image.

### 7. Cleanup

**Important:** Destroy all resources when done to avoid ongoing charges.

```bash
terraform destroy
```

Type `yes` when prompted.

---

## Cost Estimate

Running this demo in a fresh AWS account:

| Resource | Approximate Cost |
|---|---|
| NAT Gateway | ~$0.045/hr + $0.045/GB data |
| Elastic IP (while attached) | Free |
| ECS Fargate tasks | ~$0.04/hr per task (512 CPU, 1GB) |
| SQS | Free tier covers 1M requests/month |
| CloudWatch alarms | ~$0.10/alarm/month |
| Container Insights | ~$0.01/metric/month |
| ECR | Free tier covers 500MB/month |

**For a quick test (1–2 hours):** < $0.50 total. **Destroy resources when done.**

---

## Configuration

### Root Variables

| Variable | Default | Description |
|---|---|---|
| `env` | `demo` | Environment name prefix for all resources |
| `region` | `us-east-1` | AWS region |

### Base Module Variables

| Variable | Default | Description |
|---|---|---|
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `public_subnet_cidr` | `10.0.0.0/24` | Public subnet for NAT gateway |
| `private_subnet_cidrs` | `["10.0.1.0/24", "10.0.2.0/24"]` | Private subnets for ECS tasks |
| `availability_zones` | `["us-east-1a", "us-east-1b"]` | AZs for subnets |
| `container_image` | `amazon/amazon-ecs-sample` | Container image for worker tasks |
| `task_cpu` | `512` | Fargate task CPU units |
| `task_memory` | `1024` | Fargate task memory (MiB) |

### Step Scaling Variables

| Variable | Default | Description |
|---|---|---|
| `max_tasks` | `10` | Maximum ECS tasks |
| `scale_up_cooldown` | `30` | Seconds after scale-up before next action |
| `scale_down_cooldown` | `60` | Seconds after scale-down before next action |

### Target Tracking Variables

| Variable | Default | Description |
|---|---|---|
| `min_tasks` | `1` | Minimum ECS tasks (must be ≥ 1) |
| `max_tasks` | `10` | Maximum ECS tasks |
| `target_backlog_per_task` | `5` | Target SQS messages per running task |
| `scale_in_cooldown` | `120` | Seconds before allowing scale-in |
| `scale_out_cooldown` | `60` | Seconds before allowing scale-out |

---

## What Gets Created

The base module creates a complete, self-contained networking and compute stack:

```
VPC (10.0.0.0/16)
├── Public Subnet (10.0.0.0/24) ── Internet Gateway
│   └── NAT Gateway (Elastic IP)
├── Private Subnet A (10.0.1.0/24) ── Route → NAT Gateway
└── Private Subnet B (10.0.2.0/24) ── Route → NAT Gateway

ECS Cluster (Container Insights enabled)
├── Service: demo-worker-step    (Step Scaling,    desired=0, min=0,  max=10)
└── Service: demo-worker-target  (Target Tracking, desired=1, min=1,  max=10)

SQS
├── demo-worker-queue     (visibility=300s, retention=4d)
└── demo-worker-dlq       (retention=14d, maxReceiveCount=3)

IAM
├── Execution Role (ECR pull, CloudWatch Logs, CreateLogGroup)
└── Task Role (SQS ReceiveMessage, DeleteMessage, GetQueueAttributes)
```

Fargate tasks run in private subnets and reach AWS APIs (ECR, SQS, CloudWatch) via the NAT gateway.

---

## CI Pipeline

The GitHub Actions workflow (`.github/workflows/ci.yml`) runs on every push/PR to `main` that touches `terraform/` files:

| Job | Tool | What It Checks |
|---|---|---|
| **Format Check** | `terraform fmt` | HCL formatting consistency |
| **Validate** | `terraform validate` | Syntax and internal consistency |
| **TFLint** | `tflint` + AWS ruleset | AWS best practices, naming conventions, unused declarations |
| **Security Scan** | Checkov | Misconfigurations, security issues (soft-fail) |

### Run Locally

```bash
cd terraform

# Format
terraform fmt -check -recursive -diff

# Validate
terraform init -backend=false
terraform validate

# Lint
tflint --init
tflint --recursive

# Security scan
checkov -d . --framework terraform --quiet
```

---

## How It Works

### Step Scaling Flow

```
SQS messages arrive
        │
        ▼
CloudWatch Alarm evaluates: visible + in_flight >= 1
        │
        ▼
Step Scaling Policy: ExactCapacity
  1 msg → 1 task
  2 msg → 2 tasks
  ...
  10+ msg → 10 tasks (capped)
        │
        ▼
ECS service desired_count updated
        │
        ▼
Queue drains → second alarm: visible + in_flight <= 0
        │
        ▼
Scale-down policy: ExactCapacity → 0
```

### Target Tracking Flow

```
SQS messages arrive
        │
        ▼
AWS evaluates: visible_messages / running_tasks
        │
        ▼
Ratio > target_value → scale out
Ratio < target_value → scale in
        │
        ▼
AWS manages alarms and scaling automatically
```

---

## Key Design Decisions

1. **`ExactCapacity` over `ChangeInCapacity`** — prevents additive scaling on repeated alarm evaluations
2. **`ignore_changes = [desired_count]`** — stops Terraform from fighting the autoscaler
3. **`treat_missing_data = "notBreaching"`** — prevents false alarms when the queue is idle and SQS stops publishing metrics
4. **Metric math (`visible + in_flight`)** — counts total messages to prevent premature scale-down while tasks are processing
5. **Separate scale-down alarm** — dedicated alarm + policy for the zero transition, with a longer cooldown to prevent flapping
6. **NAT Gateway** — Fargate tasks in private subnets need outbound internet to pull images from ECR/Docker Hub and reach AWS APIs
7. **Container Insights enabled** — required for the `RunningTaskCount` metric used by Target Tracking

---

## Troubleshooting

| Problem | Cause | Fix |
|---|---|---|
| `terraform apply` fails on EIP | Account limit on Elastic IPs (default: 5) | Release unused EIPs or request a limit increase |
| ECS tasks stuck in PROVISIONING | NAT gateway not ready or SG blocks outbound | Check NAT gateway state and security group egress rules |
| Tasks start but immediately stop | Container image issue or missing env vars | Check CloudWatch Logs at `/ecs/demo-worker-task` |
| Step scaling not reacting | Alarm in INSUFFICIENT_DATA | Wait 2–3 minutes for SQS metrics to populate |
| Target tracking not scaling | Container Insights metrics not available yet | Wait 5 minutes after first task runs for metrics to appear |
| `AccessDeniedException` on apply | IAM permissions insufficient | Use an IAM user/role with admin access or add the specific permissions listed in Prerequisites |

---

## Suggested GitHub Settings

| Setting | Value |
|---|---|
| **Repo name** | `ecs-sqs-autoscaling-terraform` |
| **Description** | Terraform modules for ECS Fargate autoscaling with SQS — Step Scaling and Target Tracking with scale-from-zero |
| **Topics** | `terraform`, `aws`, `ecs`, `fargate`, `autoscaling`, `sqs`, `step-scaling`, `target-tracking`, `infrastructure-as-code`, `devops` |
| **Visibility** | Public |
| **License** | Apache 2.0 |
| **Branch protection** | Require CI to pass before merge on `main` |

---

## Contributing

1. Fork the repo
2. Create a feature branch
3. Ensure CI passes (`terraform fmt`, `validate`, `tflint`, `checkov`)
4. Open a PR

---

## License

[Apache License 2.0](LICENSE)

---

## Author

**Hiren Timbadiya** — [GitHub](https://github.com/hirentimbadiya)
