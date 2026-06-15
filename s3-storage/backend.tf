terraform {
  backend "s3" {
    bucket         = "yusmoj-controls-dev-terraform-state"
    key            = "s3-storage/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}
