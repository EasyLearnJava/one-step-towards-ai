###############################################################################
# FILE PURPOSE
#   Creates the AWS resources for the Python API (version 2). Piece 2.6 adds
#   the private ECR repository that stores the API's Docker images.
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
