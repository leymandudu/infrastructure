terraform {
  backend "s3" {
    bucket         = "yusmoj-dev-terraform-state"
    key            = "security-groups/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "yusmoj-dev-terraform-locks"
    encrypt        = true
  }
}
