variable "project" {
  description = "Project name"
  type        = string
  default     = "yusmoj-controls"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}


variable "vpc_id" {
  description = "VPC ID to use for resources"
  type        = string
  default     = "vpc-03957e880e32fb2ad"
}

variable "acm_certificate_arn" {
  description = "ARN of ACM certificate for HTTPS on the ALB (must cover controls.yusmojsolutions.com)"
  type        = string
  default     = ""
}
