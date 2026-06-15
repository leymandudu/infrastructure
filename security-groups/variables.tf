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
  description = "VPC ID to use for security groups"
  type        = string
  default     = "vpc-03957e880e32fb2ad"
}
