variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "yusmoj-controls"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}
