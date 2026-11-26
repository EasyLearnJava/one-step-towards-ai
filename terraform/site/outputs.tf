###############################################################################
# FILE PURPOSE
#   Publishes the most useful values created or discovered by this Terraform
#   configuration after an apply succeeds.
#
# DEPENDENCIES
#   - main.tf: provides the CloudFront, S3, IAM, and AWS account resources
#     referenced here.
#
# WHY THIS FILE EXISTS
#   Outputs give users and automation a stable way to obtain the website URL,
#   bucket name, deployment role, and account ID without inspecting AWS manually.
###############################################################################

# ---------------------------------------------------------------------------
# PUBLIC WEBSITE ADDRESS
# CloudFront provides HTTPS and is the public entry point for the private S3
# site bucket.
# ---------------------------------------------------------------------------
output "website_url" {
  description = "HTTPS address of the website."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

# ---------------------------------------------------------------------------
# DEPLOYMENT AND ACCOUNT DETAILS
# These values are used to configure GitHub variables or verify which AWS
# account and bucket Terraform deployed to.
# ---------------------------------------------------------------------------
output "site_bucket_name" {
  value = aws_s3_bucket.site.id
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# API (VERSION 2)
# The repository URL becomes the GitHub variable API_ECR_REPOSITORY; the
# region may be kept as API_REGION for reference; the Deploy workflow reads
# the region from the repository URL and does not need it.
# ---------------------------------------------------------------------------
output "api_ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "api_region" {
  value = local.api_region
}

# The function name becomes the GitHub variable API_FUNCTION_NAME (2.8). The
# function URL is private: calling it directly must return 403.
output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

output "api_function_url" {
  value = aws_lambda_function_url.api.function_url
}
