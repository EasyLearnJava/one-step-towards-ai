###############################################################################
# FILE PURPOSE
#   Defines the Terraform and AWS provider requirements and the remote state
#   location. This file must be loaded by Terraform before any resource in
#   main.tf can be initialized.
#
# DEPENDENCIES
#   - variables.tf: provides aws_region and environment for the AWS providers.
#   - An environment backend file supplies the S3 state bucket and state key.
#     Examples are in terraform/environments/{staging,production}/.
#
# WHY THIS FILE EXISTS
#   It keeps Terraform versions, AWS provider versions, remote state storage,
#   and provider regions consistent across local machines and GitHub Actions.
###############################################################################

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Encrypt Terraform state before storing it in the S3 state bucket.
    encrypt = true

    # Use S3 native state locking so concurrent Terraform runs cannot modify state together.
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "one-step-at-a-time"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "monitoring"
  region = "us-east-1"
}
