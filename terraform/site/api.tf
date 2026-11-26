###############################################################################
# FILE PURPOSE
#   Creates the AWS resources for the Python API (version 2). Piece 2.6 adds
#   the private ECR repository that stores the API's Docker images; piece 2.8
#   adds the Lambda function that runs the newest image, its log group, its
#   execution role and its private function URL.
#
# DEPENDENCY RELATIONSHIPS
#   - versions.tf: the aws.api provider places these resources in us-east-2.
#   - main.tf: the GitHub deploy role is granted push access to this
#     repository in its deploy policy.
#   - outputs.tf: publishes the repository URL and region for GitHub.
#
# WHY THIS FILE EXISTS
#   It keeps the API resources apart from the version 1 website resources.
#   The API lives in us-east-2 because the organization's region rule blocks
#   Lambda in us-east-1, and Lambda can only pull images from ECR in its own
#   region.
###############################################################################

# ---------------------------------------------------------------------------
# PRIVATE IMAGE REPOSITORY
# Holds the API images, each tagged with its commit SHA by the deploy
# workflow. Images are scanned for known vulnerabilities when pushed. This is
# a disposable environment, like the website bucket: destroying it also
# deletes every image in it.
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "api" {
  provider             = aws.api
  name                 = "one-step-${var.environment}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# ---------------------------------------------------------------------------
# IMAGE CLEAN-UP
# Keeps only the newest 5 images so storage cost stays at a few cents. Older
# images are deleted automatically, about once a day.
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "api" {
  provider   = aws.api
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ---------------------------------------------------------------------------
# STARTING IMAGE
# The function is created from the newest image in the repository (pushed by
# the Deploy workflow, piece 2.7). After that, the Deploy workflow ships new
# images and Terraform ignores the image (see lifecycle below). The image is
# pinned by digest, so a later push cannot change it silently.
# ---------------------------------------------------------------------------
data "aws_ecr_image" "api_start" {
  provider        = aws.api
  repository_name = aws_ecr_repository.api.name
  most_recent     = true
}

# ---------------------------------------------------------------------------
# LOG GROUP
# Everything the API prints goes to CloudWatch Logs, kept for 14 days.
# Created here, before the function, so Lambda does not create one that
# keeps logs forever.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "api" {
  provider          = aws.api
  name              = "/aws/lambda/one-step-${var.environment}-api"
  retention_in_days = 14
}

# ---------------------------------------------------------------------------
# EXECUTION ROLE
# The identity the function runs as. It may only write its own logs: no S3,
# no other AWS access. Step 3 adds what the AI calls need.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "api_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "one-step-${var.environment}-api"
  assume_role_policy = data.aws_iam_policy_document.api_trust.json
}

data "aws_iam_policy_document" "api_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }
}

resource "aws_iam_role_policy" "api_logs" {
  name   = "write-logs"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api_logs.json
}

# ---------------------------------------------------------------------------
# LAMBDA FUNCTION
# Runs the Docker image. The Lambda Web Adapter inside the image turns each
# invocation into a normal HTTP request to uvicorn, after /api/health answers.
# Reserved concurrency 5 caps how many copies run at once: a cost and abuse
# limit (the account allows 400 in us-east-2).
# ---------------------------------------------------------------------------
resource "aws_lambda_function" "api" {
  provider      = aws.api
  function_name = "one-step-${var.environment}-api"
  role          = aws_iam_role.api.arn
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.api_start.image_uri
  architectures = ["x86_64"]
  memory_size   = 512
  timeout       = 15

  reserved_concurrent_executions = 5

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  depends_on = [aws_iam_role_policy.api_logs]

  lifecycle {
    # The Deploy workflow ships new code (piece 2.10); Terraform must not
    # roll the function back to the starting image.
    ignore_changes = [image_uri]
  }
}

# ---------------------------------------------------------------------------
# PRIVATE FUNCTION URL
# An HTTPS address for the function. AWS_IAM means every call must be signed
# by an AWS identity allowed to invoke it; nobody is allowed yet, so a direct
# call returns 403. Piece 2.9 lets only CloudFront call it.
# ---------------------------------------------------------------------------
resource "aws_lambda_function_url" "api" {
  provider           = aws.api
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "AWS_IAM"
}

# ---------------------------------------------------------------------------
# CLOUDFRONT TO LAMBDA: SIGNED REQUESTS (piece 2.9)
# CloudFront signs every request it sends to the function URL (Origin Access
# Control, origin type lambda). With AWS_IAM auth, Lambda then accepts the
# request only because of the two permissions below. POST requests (step 3)
# must also carry x-amz-content-sha256, the SHA-256 of the body.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "api" {
  name                              = "one-step-${var.environment}-api"
  description                       = "Signed access to the private API function URL."
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# INVOKE PERMISSIONS FOR THIS DISTRIBUTION ONLY
# Current AWS docs require both actions for CloudFront to call a function
# URL: InvokeFunctionUrl and InvokeFunction. source_arn limits both to this
# one CloudFront distribution; no other caller is allowed.
# ---------------------------------------------------------------------------
resource "aws_lambda_permission" "cloudfront_url" {
  provider               = aws.api
  statement_id           = "AllowCloudFrontServicePrincipal"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.site.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  provider      = aws.api
  statement_id  = "AllowCloudFrontServicePrincipalInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.site.arn
}
