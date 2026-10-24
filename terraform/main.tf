terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment to store state in S3 (recommended before sharing with a team).
  # Create the bucket manually first — Terraform cannot create its own backend bucket.
  # backend "s3" {
  #   bucket  = "your-terraform-state-bucket"
  #   key     = "taskflow/terraform.tfstate"
  #   region  = "us-east-1"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region

  # These tags are applied to every resource automatically.
  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

locals {
  name_prefix = var.project_name
}
