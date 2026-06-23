variable "project" {
  type    = string
  default = "yusmoj-controls"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "contact_email" {
  description = "Verified SES email address that receives contact form submissions"
  type        = string
  default     = "info@yusmojsolutions.com"
}

variable "allowed_origin" {
  description = "CORS allowed origin for the API (CloudFront domain or custom domain)"
  type        = string
  default     = "https://www.yusmojsolutions.com"
}

variable "allowed_origins" {
  description = "Optional list of CORS allowed origins; when set, this overrides allowed_origin"
  type        = list(string)
  default     = []
}
