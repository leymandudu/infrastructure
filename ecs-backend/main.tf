########################################
# Layer 3: ECS Backend — Cluster, Task, Service, ALB, SSM, IAM
########################################

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
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "ecs-backend"
    }
  }
}

# ─── Remote State Data Sources ────────────────────────────────────────

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "vpc-networking/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "ecr" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "ecr/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "security_groups" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "security-groups/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "s3_storage" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "s3-storage/terraform.tfstate"
    region = var.aws_region
  }
}

data "aws_caller_identity" "current" {}

# ─── SSM Parameter Store — Secrets & Config ──────────────────────────

resource "aws_ssm_parameter" "database_url" {
  name        = "/${var.project}/${var.environment}/DATABASE_URL"
  description = "Neon PostgreSQL connection string"
  type        = "SecureString"
  value       = var.database_url

  tags = {
    Name = "${var.project}-database-url"
  }
}

resource "aws_ssm_parameter" "jwt_secret" {
  name        = "/${var.project}/${var.environment}/JWT_SECRET"
  description = "JWT signing secret"
  type        = "SecureString"
  value       = var.jwt_secret

  tags = {
    Name = "${var.project}-jwt-secret"
  }
}

resource "aws_ssm_parameter" "node_env" {
  name        = "/${var.project}/${var.environment}/NODE_ENV"
  description = "Node environment"
  type        = "String"
  value       = "production"
}

resource "aws_ssm_parameter" "port" {
  name        = "/${var.project}/${var.environment}/PORT"
  description = "Application port"
  type        = "String"
  value       = "5000"
}

# ─── CloudWatch Log Group ────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project}-${var.environment}-backend"
  retention_in_days = 14

  tags = {
    Name = "${var.project}-backend-logs"
  }
}

# ─── IAM: ECS Task Execution Role ────────────────────────────────────

resource "aws_iam_role" "ecs_execution" {
  name = "${var.project}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_base" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow ECS to read SSM parameters (secrets)
resource "aws_iam_role_policy" "ecs_execution_ssm" {
  name = "${var.project}-${var.environment}-ecs-ssm-policy"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameters",
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.environment}/*"
      }
    ]
  })
}

# ─── IAM: ECS Task Role (app-level permissions) ──────────────────────

resource "aws_iam_role" "ecs_task" {
  name = "${var.project}-${var.environment}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Allow the app to read/write to the uploads S3 bucket
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.project}-${var.environment}-ecs-s3-uploads-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          data.terraform_remote_state.s3_storage.outputs.uploads_bucket_arn,
          "${data.terraform_remote_state.s3_storage.outputs.uploads_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ─── ECS Cluster ─────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Name = "${var.project}-${var.environment}-cluster"
  }
}

# ─── ECS Task Definition ─────────────────────────────────────────────

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-${var.environment}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512    # 0.5 vCPU
  memory                   = 1024   # 1 GB
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "${var.project}-backend"
      image     = "${data.terraform_remote_state.ecr.outputs.repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]

      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_ssm_parameter.database_url.arn
        },
        {
          name      = "JWT_SECRET"
          valueFrom = aws_ssm_parameter.jwt_secret.arn
        }
      ]

      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = "5000"
        },
        {
          name  = "S3_UPLOADS_BUCKET"
          value = data.terraform_remote_state.s3_storage.outputs.uploads_bucket_id
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:5000/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = "${var.project}-${var.environment}-backend-task"
  }
}

# ─── Application Load Balancer ────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.terraform_remote_state.security_groups.outputs.alb_sg_id]
  subnets            = data.terraform_remote_state.vpc.outputs.public_subnet_ids

  tags = {
    Name = "${var.project}-${var.environment}-alb"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "${var.project}-${var.environment}-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
  }

  tags = {
    Name = "${var.project}-${var.environment}-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ─── ECS Service ─────────────────────────────────────────────────────

resource "aws_ecs_service" "backend" {
  name            = "${var.project}-${var.environment}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.vpc.outputs.public_subnet_ids
    security_groups  = [data.terraform_remote_state.security_groups.outputs.ecs_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "${var.project}-backend"
    container_port   = 5000
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 120

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Name = "${var.project}-${var.environment}-backend-service"
  }
}
