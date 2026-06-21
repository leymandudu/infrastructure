########################################
# Route 53 — DNS for yusmojsolutions.com
# Manages hosted zone + DNS records for:
#   yusmojsolutions.com       → Yusmoj Solutions website (CloudFront)
#   www.yusmojsolutions.com   → Yusmoj Solutions website (CloudFront)
#   controls.yusmojsolutions.com → Project Controls app (CloudFront)
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
      Layer       = "route53"
    }
  }
}

# ─── Remote State: Yusmoj Solutions Website CloudFront ───────────────

data "terraform_remote_state" "yusmoj_solutions_website" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "yusmoj-solutions-website/terraform.tfstate"
    region = var.aws_region
  }
}

# ─── Remote State: Project Controls CloudFront ───────────────────────

data "terraform_remote_state" "cloudfront" {
  backend = "s3"
  config = {
    bucket = "${var.project}-${var.environment}-terraform-state"
    key    = "cloudfront/terraform.tfstate"
    region = var.aws_region
  }
}

# ─── Hosted Zone ─────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = "yusmojsolutions.com"

  tags = {
    Name = "yusmojsolutions.com"
  }
}

# ─── ACM Certificate DNS Validation Records ──────────────────────────
# After requesting the certificate, paste the CNAME name/value pairs
# from ACM Console here, or use aws_acm_certificate_validation resource.

# ─── yusmojsolutions.com → Yusmoj Solutions website ─────────────────

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "yusmojsolutions.com"
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.yusmoj_solutions_website.outputs.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2" # CloudFront hosted zone ID (always this value)
    evaluate_target_health = false
  }
}

# ─── www.yusmojsolutions.com → Yusmoj Solutions website ──────────────

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.yusmojsolutions.com"
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.yusmoj_solutions_website.outputs.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}

# ─── controls.yusmojsolutions.com → Project Controls app ─────────────

resource "aws_route53_record" "controls" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "controls.yusmojsolutions.com"
  type    = "A"

  alias {
    name                   = data.terraform_remote_state.cloudfront.outputs.cloudfront_domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
}
