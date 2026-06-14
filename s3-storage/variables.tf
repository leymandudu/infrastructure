variable "project" {
  description = "Project name"
  type        = string
  default     = "yusmoj"
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

variable "cors_allowed_origins" {
  description = "Allowed origins for uploads bucket CORS"
  type        = list(string)
  default     = ["*"]
}
