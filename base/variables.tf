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

variable "github_repositories" {
  description = "List of GitHub repositories allowed to assume the IAM role via OIDC"
  type        = list(string)
  default     = ["leymandudu/ProjectControls", "leymandudu/infrastructure"]
}
