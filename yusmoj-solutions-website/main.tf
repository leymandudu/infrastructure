########################################
# Yusmoj Solutions Website — S3 + CloudFront
# Dedicated bucket for www.yusmojsolutions.com
# Shares Terraform state backend and IAM role with other infrastructure layers
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
      Layer       = "yusmoj-solutions-website"
    }
  }
}

data "aws_caller_identity" "current" {}

# ─── S3 Website Bucket ───────────────────────────────────────────────

resource "aws_s3_bucket" "website" {
  bucket = "yusmoj-solutions-website-${var.environment}"

  tags = {
    Name = "yusmoj-solutions-website-${var.environment}"
  }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─── CloudFront Origin Access Control ────────────────────────────────

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "yusmoj-solutions-website-${var.environment}-oac"
  description                       = "OAC for Yusmoj Solutions website S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─── S3 Bucket Policy — Allow CloudFront OAC only ────────────────────

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

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
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# ─── Cache Policies ──────────────────────────────────────────────────

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

# ─── Security Response Headers Policy ───────────────────────────────

resource "aws_cloudfront_response_headers_policy" "security" {
  name = "yusmoj-solutions-security-headers-${var.environment}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=()"
      override = true
    }
  }
}

# ─── CloudFront Distribution ─────────────────────────────────────────

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "yusmoj-solutions ${var.environment} - www.yusmojsolutions.com"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.acm_certificate_arn != "" ? ["www.yusmojsolutions.com", "yusmojsolutions.com"] : []

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-yusmoj-solutions-website"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods              = ["GET", "HEAD", "OPTIONS"]
    cached_methods               = ["GET", "HEAD"]
    target_origin_id             = "s3-yusmoj-solutions-website"
    viewer_protocol_policy       = "redirect-to-https"
    compress                     = true
    cache_policy_id              = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id   = aws_cloudfront_response_headers_policy.security.id
  }

  # SPA routing — redirect 403/404 back to index.html for client-side routing
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

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = var.acm_certificate_arn != "" ? "TLSv1.2_2021" : null
  }

  tags = {
    Name = "yusmoj-solutions-website-${var.environment}"
  }
}
