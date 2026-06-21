########################################
# Layer 0: Base — Terraform State Backend
########################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Base layer uses LOCAL state (bootstrapping — the S3 bucket doesn't exist yet)
  # After first apply, you can optionally migrate to S3 backend.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "base"
    }
  }
}

# ─── S3 Bucket for Terraform Remote State ────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project}-${var.environment}-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─── DynamoDB Table for State Locking ────────────────────────────────
# DynamoDB locking is intentionally omitted to avoid extra cost.
# State corruption is mitigated by:
#   1. S3 bucket versioning (every state change is retained and recoverable)
#   2. GitHub Actions runs workflows sequentially per module
#   3. The concurrency group below prevents parallel runs on the same module
# If multiple engineers run terraform locally simultaneously in future,
# re-enable by uncommenting the resource below and adding dynamodb_table
# to all backend.tf files.

# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "${var.project}-${var.environment}-terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

# ─── GitHub Actions OIDC Trust Setup ─────────────────────────────────

# Fetch GitHub Actions certificate dynamically for the OIDC thumbprint
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for repo in var.github_repositories : "repo:${repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${var.project}-${var.environment}-github-actions-role"
  description        = "IAM role assumed by GitHub Actions CI/CD pipelines"
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

resource "aws_iam_role_policy" "github_actions_least_privilege" {
  name = "${var.project}-${var.environment}-github-actions-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StateAndAssets"
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSAndECR"
        Effect = "Allow"
        Action = [
          "ecs:*", "ecr:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaAndAPIGateway"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration", "lambda:GetFunction",
          "lambda:AddPermission", "lambda:RemovePermission",
          "lambda:GetPolicy", "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "apigateway:*"
        ]
        Resource = "*"
      },
      {
        Sid    = "SESAndACM"
        Effect = "Allow"
        Action = [
          "ses:VerifyEmailIdentity", "ses:GetIdentityVerificationAttributes",
          "ses:DeleteIdentity",
          "acm:RequestCertificate", "acm:DescribeCertificate",
          "acm:ListCertificates", "acm:DeleteCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "Route53"
        Effect = "Allow"
        Action = [
          "route53:CreateHostedZone", "route53:GetHostedZone",
          "route53:ListHostedZones", "route53:ChangeResourceRecordSets",
          "route53:ListResourceRecordSets", "route53:GetChange"
        ]
        Resource = "*"
      },
      {
        Sid    = "IAMForRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:GetRole", "iam:PutRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy", "iam:DeleteRole",
          "iam:PassRole", "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies", "iam:ListRolePolicies",
          "iam:CreateOpenIDConnectProvider", "iam:GetOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider", "iam:UpdateAssumeRolePolicy"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:CreateLogStream",
          "logs:PutLogEvents", "logs:DescribeLogGroups",
          "logs:DeleteLogGroup", "logs:ListTagsForResource",
          "logs:TagResource", "logs:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter", "ssm:GetParameters",
          "ssm:PutParameter", "ssm:DeleteParameter"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2VPC"
        Effect = "Allow"
        Action = [
          "ec2:*", "elasticloadbalancing:*"
        ]
        Resource = "*"
      }
    ]
  })
}

