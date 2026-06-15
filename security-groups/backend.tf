terraform {
  backend "s3" {
    bucket         = "yusmoj-controls-dev-terraform-state"
    key            = "security-groups/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
