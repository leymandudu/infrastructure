terraform {
  backend "s3" {
    bucket         = "yusmoj-controls-dev-terraform-state"
    key            = "ecs-backend/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
  }
}