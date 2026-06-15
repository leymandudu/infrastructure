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

variable "database_url" {
  description = "Neon PostgreSQL connection string"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret"
  type        = string
  sensitive   = true
}

variable "vpc_id" {
  description = "VPC ID to use for resources"
  type        = string
  default     = "vpc-03957e880e32fb2ad"
}
