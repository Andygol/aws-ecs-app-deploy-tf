terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.63.0"
    }
  }
  required_version = ">= 1.0.0"

  # Uncomment to use remote state
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "state/terraform.tfstate"
  #   region         = "eu-central-1"
  #   encrypt        = true
  #   kms_key_id     = "alias/terraform-bucket-key"
  #   dynamodb_table = "terraform-state-lock"
  # }
}

# Common tags

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.app_name
    Terraform   = "true"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }

  merged_tags = { for k, v in local.common_tags : k => v }
}

# Specify the provider and access details
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region

  default_tags {
    tags = local.merged_tags
  }
}
