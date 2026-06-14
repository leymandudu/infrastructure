########################################
# Layer 4: CloudFront — CDN, SPA + API Proxy
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
      Layer       = "cloudfront"
    }
  }
}

# ─── Remote State Data Sources ────────────────────────────────────────

data "terraform_remote_state" "s3_storage" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "s3-storage/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "ecs_backend" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "ecs-backend/terraform.tfstate"
    region = var.aws_region
  }
}

# ─── Origin Access Control (S3) ──────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project}-${var.environment}-s3-oac"
  description                       = "OAC for frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─── S3 Bucket Policy — Allow CloudFront OAC ─────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = data.terraform_remote_state.s3_storage.outputs.frontend_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${data.terraform_remote_state.s3_storage.outputs.frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

# ─── Cache Policies ──────────────────────────────────────────────────

# Use AWS managed CachingOptimized policy for static assets
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# Use AWS managed CachingDisabled policy for API
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Use AWS managed AllViewerExceptHostHeader origin request policy for API
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ─── CloudFront Distribution ─────────────────────────────────────────

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project} ${var.environment} — SPA + API"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # ── Origin 1: S3 Frontend (default) ──────────────────────────────
  origin {
    domain_name              = data.terraform_remote_state.s3_storage.outputs.frontend_bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  # ── Origin 2: ALB Backend (API) ─────────────────────────────────
  origin {
    domain_name = data.terraform_remote_state.ecs_backend.outputs.alb_dns_name
    origin_id   = "alb-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── Default Behavior: S3 (Frontend SPA) ──────────────────────────
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  # ── Ordered Behavior: /api/* → ALB ──────────────────────────────
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = false
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # ── /health → ALB (for monitoring) ──────────────────────────────
  ordered_cache_behavior {
    path_pattern             = "/health"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "redirect-to-https"
    compress                 = false
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # ── SPA Routing: 403/404 → index.html ──────────────────────────
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  # ── Restrictions ────────────────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ── Default CloudFront certificate (*.cloudfront.net) ───────────
  # Replace with ACM certificate when custom domain is configured
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project}-${var.environment}-cloudfront"
  }
}
