########################################
# Contact API — API Gateway + Lambda + SES
# Receives contact form submissions from www.yusmojsolutions.com
# and delivers them to info@yusmojsolutions.com via AWS SES
########################################

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
      Layer       = "contact-api"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  allowed_origins = length(var.allowed_origins) > 0 ? var.allowed_origins : [var.allowed_origin]
}

# ─── SES Email Identity ───────────────────────────────────────────────
# NOTE: After first apply, go to SES Console and verify info@yusmojsolutions.com
# Once the domain is verified in Route 53, domain-level verification is preferred.

resource "aws_ses_email_identity" "contact" {
  email = var.contact_email
}

# ─── Lambda Execution Role ────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${var.project}-${var.environment}-contact-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ses" {
  name = "${var.project}-${var.environment}-contact-lambda-ses"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ses:SendEmail"
      Resource = "arn:aws:ses:${var.aws_region}:${data.aws_caller_identity.current.account_id}:identity/${var.contact_email}"
    }]
  })
}

# ─── Lambda Function ─────────────────────────────────────────────────

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/lambda/handler.zip"
}

resource "aws_lambda_function" "contact" {
  function_name    = "${var.project}-${var.environment}-contact-handler"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 10

  # No Lambda Function URL configured — invoked exclusively via API Gateway.
  # Access is controlled by the aws_lambda_permission resource below.

  environment {
    variables = {
      CONTACT_EMAIL  = var.contact_email
      ALLOWED_ORIGIN = var.allowed_origin
      ALLOWED_ORIGINS = join(",", local.allowed_origins)
    }
  }
}

# ─── API Gateway (HTTP API) ───────────────────────────────────────────

resource "aws_apigatewayv2_api" "contact" {
  name          = "${var.project}-${var.environment}-contact-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = local.allowed_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.contact.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.contact.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post" {
  api_id    = aws_apigatewayv2_api.contact.id
  route_key = "POST /contact"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.contact.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.contact.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.contact.execution_arn}/*/*"
}
