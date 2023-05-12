provider "aws" {
  region = var.aws_region
}

locals {
  app_name = "infrustructure_test"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# VPC and Subnets

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name = local.app_name
  cidr = "10.0.0.0/16"

  azs             = ["${data.aws_region.current.name}a", "${data.aws_region.current.name}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "aws_security_group" "allow_all" {
  name        = "allow_all"
  description = "Allow all traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECR repository

resource "aws_ecr_repository" "this" {
  name = local.app_name
}

# ECS cluster

resource "aws_ecs_cluster" "this" {
  name = local.app_name
}

# ECS task definition and execution role

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs_execution_role"

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

resource "aws_iam_role" "ecs_events" {
  name = "ecs_events_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_events" {
  name = "ecs_events_policy"
  role = aws_iam_role.ecs_events.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:RunTask",
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_security_group" "ecs_tasks_sg" {
  name        = "ecs_tasks_security_group"
  description = "Security group for ECS tasks"
  vpc_id      = module.vpc.vpc_id
}


resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  role       = aws_iam_role.ecs_execution_role.name
}

resource "aws_iam_role" "ecs_task_role" {
  name = "ecs_task_role"

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

resource "aws_ecs_task_definition" "this" {
  family                   = local.app_name
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "2048"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions = jsonencode([{
    name      = local.app_name
    image     = "${aws_ecr_repository.this.repository_url}:latest"
    essential = true
  }])
}

# ECS service

resource "aws_ecs_service" "this" {
  name            = local.app_name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.public_subnets
    assign_public_ip = true
  }
}

# AWS CodePipeline and CodeBuild

resource "aws_codebuild_project" "this" {
  name          = local.app_name
  build_timeout = "5"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/amazonlinux2-x86_64-standard:3.0"
    type         = "LINUX_CONTAINER"

  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_codestarconnections_connection" "github" {
  provider_type = "GitHub"
  name          = "github-connection"
}


resource "aws_codepipeline" "this" {
  name     = local.app_name
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_username}/${var.github_repository}"
        BranchName       = var.github_branch
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.this.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.this.name
        ServiceName = aws_ecs_service.this.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}

# IAM roles, policies, and S3 bucket

resource "aws_iam_role" "codebuild_role" {
  name = "codebuild_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_role_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  role       = aws_iam_role.codebuild_role.name
}

resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name = "codepipeline_policy"
  role = aws_iam_role.codepipeline_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ecr:DescribeImages",
          "ecs:DescribeServices",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "random_id" "id" {
  byte_length = 4
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "codepipeline-infrustructure-test-${random_id.id.hex}"
  force_destroy = true
}


# Amazon EventBridge

resource "aws_cloudwatch_event_rule" "daily_schedule" {
  name                = "daily-schedule"
  schedule_expression = "cron(0 0 * * ? *)"
}

resource "aws_cloudwatch_event_target" "ecs_target" {
  rule      = aws_cloudwatch_event_rule.daily_schedule.name
  target_id = "ecs_target"
  arn       = aws_ecs_cluster.this.arn
  role_arn  = aws_iam_role.ecs_events.arn

  ecs_target {
    task_count          = 1
    task_definition_arn = aws_ecs_task_definition.this.arn
    launch_type         = "FARGATE"

    network_configuration {
      security_groups  = [aws_security_group.ecs_tasks_sg.id]
      subnets          = module.vpc.private_subnets
      assign_public_ip = false
    }
  }

  input_transformer {
    input_paths = {
      instance = "$.detail.instance"
    }

    input_template = <<EOF
    {
      "containerOverrides": [
        {
          "name": "container_name",
          "command": ["python", "app.py"]
        }
      ]
    }
    EOF
  }
}


resource "aws_cloudwatch_event_permission" "ecs_event_permission" {
  action       = "events:PutEvents"
  principal    = "*"
  statement_id = "ECS_Events"
}


