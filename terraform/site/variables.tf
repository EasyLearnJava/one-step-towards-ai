###############################################################################
# FILE PURPOSE
#   Declares all user-supplied configuration values for this Terraform site.
#   Each value receives its actual setting from a staging or production
#   .tfvars file.
#
# DEPENDENCIES
#   - terraform/environments/staging/site.example.tfvars
#   - terraform/environments/production/site.example.tfvars
#   - versions.tf: uses aws_region and environment in the AWS provider.
#   - main.tf: consumes every variable declared here.
#   - outputs.tf: does not consume variables directly.
#
# WHY THIS FILE EXISTS
#   Variables separate infrastructure code from environment-specific values,
#   allowing staging and production to reuse the same resources safely.
###############################################################################

# ---------------------------------------------------------------------------
# AWS LOCATION AND ENVIRONMENT
# These values identify where resources are created and which deployment
# environment is being managed.
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region for the website bucket and deployment role."
  type        = string
}

variable "environment" {
  description = "Deployment environment; must match the GitHub environment name."
  type        = string

  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "Use staging or production."
  }
}

# ---------------------------------------------------------------------------
# WEBSITE STORAGE
# This must be globally unique across all AWS accounts because S3 bucket
# names form a shared global namespace.
# ---------------------------------------------------------------------------
variable "site_bucket_name" {
  description = "Globally unique S3 bucket name for the website."
  type        = string
}

# ---------------------------------------------------------------------------
# GITHUB OIDC TRUST
# GitHub Actions receives temporary AWS credentials through OIDC. These values
# restrict which repository and GitHub environment may assume the deployment
# role created in main.tf.
# ---------------------------------------------------------------------------
variable "github_repository" {
  description = "GitHub repository as GitHub puts it in the OIDC subject: owner/name, or owner@ownerId/name@repoId."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+(@[0-9]+)?/[A-Za-z0-9_.-]+(@[0-9]+)?$", var.github_repository))
    error_message = "Use owner/name, or owner@ownerId/name@repoId as shown in the OIDC subject."
  }
}

variable "github_oidc_provider_arn" {
  description = "ARN of the existing GitHub Actions OIDC provider in this AWS account."
  type        = string
}

# ---------------------------------------------------------------------------
# AVAILABILITY ALERTING
# Route 53 health-check failures send notifications through SNS. The owner
# of the email address must confirm the subscription before alerts arrive.
# ---------------------------------------------------------------------------
variable "alert_email" {
  description = "Email address for availability alerts; the SNS subscription requires confirmation."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Provide a valid alert email address."
  }
}
