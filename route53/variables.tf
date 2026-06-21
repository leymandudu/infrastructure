variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

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

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate covering yusmojsolutions.com, www.yusmojsolutions.com, controls.yusmojsolutions.com"
  type        = string
}
