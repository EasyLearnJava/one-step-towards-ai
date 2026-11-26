###############################################################################
# FILE PURPOSE
#   Creates all AWS resources required to host and monitor the static website.
#   This includes private S3 storage, CloudFront delivery, secure headers,
#   GitHub deployment permissions, health checks, and availability alerts.
#
# DEPENDENCY RELATIONSHIPS
#   - versions.tf: initializes Terraform, the AWS providers, and remote state.
#   - variables.tf: supplies environment, bucket, OIDC, repository, and alert
#     values used throughout this file.
#   - outputs.tf: reads resource IDs and names created here and publishes them.
#   - A .tfvars file in terraform/environments/{staging,production}/ supplies
#     the actual values for the declared variables.
#   - A backend .hcl file supplies the remote Terraform state location.
#
# WHY THIS FILE EXISTS
#   It defines the website infrastructure as code so the same repeatable setup
#   can be created for staging and production with environment-specific values.
###############################################################################

# ---------------------------------------------------------------------------
# AWS ACCOUNT CONTEXT
# The current AWS account is queried for outputs and deployment verification.
# This data source does not create or change any AWS resource.
# ---------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# PRIVATE WEBSITE BUCKET
# S3 stores the index.html file. The bucket is not public: CloudFront will be
# the only public delivery path. Versioning enables recovery of prior objects.
# This is a disposable site: destruction permanently removes every object
# version and delete marker in this bucket.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "site" {
  bucket        = var.site_bucket_name
  force_destroy = true
}

# ---------------------------------------------------------------------------
# PUBLIC ACCESS PROTECTION
# All public ACL and bucket-policy paths are blocked. This defense prevents
# accidental direct access to the private S3 website bucket.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# BUCKET OWNERSHIP
# BucketOwnerEnforced makes the bucket owner the sole owner of uploaded objects
# and disables bucket ACL behavior that is no longer needed.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ---------------------------------------------------------------------------
# OBJECT VERSIONING
# Every uploaded object receives a version. This supports rollback and protects
# against accidental replacement or deletion while Terraform is in use.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------------------
# BUCKET ENCRYPTION
# AES256 server-side encryption protects objects at rest with an AWS-managed
# encryption key. It does not replace HTTPS or AWS IAM/OAC access controls.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# CLOUDFRONT ORIGIN ACCESS CONTROL
# OAC signs requests from CloudFront to S3. It proves that the request came
# from the configured CloudFront distribution instead of exposing the bucket.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "one-step-${var.environment}"
  description                       = "Signed access to the private website bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# CLOUD SECURITY HEADERS
# These headers instruct browsers to use HTTPS, block framing, suppress
# MIME-type guessing, reduce referrer disclosure, and apply a restrictive
# Content Security Policy.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_response_headers_policy" "site" {
  name = "one-step-${var.environment}-security"

  security_headers_config {
    content_security_policy {
      content_security_policy = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
      override                = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }
}

# ---------------------------------------------------------------------------
# CACHING POLICY
# Caching is disabled initially so a newly uploaded index.html appears
# immediately. This is a learning-friendly starting point rather than a
# permanent requirement for a larger static site.
# ---------------------------------------------------------------------------
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# ---------------------------------------------------------------------------
# CLOUDFRONT WEBSITE DISTRIBUTION
# CloudFront receives visitor requests, redirects HTTP to HTTPS, retrieves
# objects from the private S3 origin, adds security headers, and serves
# index.html as the default page.
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "One Step At A Time - ${var.environment}"

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "private-site"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "private-site"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
    compress                   = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------------------------------------------------------------------------
# PRIVATE BUCKET POLICY
# These statements authorize only this CloudFront distribution to GetObject.
# The second statement prevents any S3 request that does not use TLS.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid     = "AllowOnlyThisCloudFrontDistribution"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.site.arn}/*"
    ]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ---------------------------------------------------------------------------
# ATTACH BUCKET POLICY
# This attaches the policy document to the website bucket. CloudFront access
# therefore depends on both OAC signing and this matching SourceArn condition.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}

# ---------------------------------------------------------------------------
# GITHUB OIDC TRUST POLICY
# OIDC allows GitHub Actions to receive temporary AWS credentials. The aud
# and sub conditions limit trust to this AWS account's GitHub provider and the
# exact repository/environment pair.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "github_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.github_oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:environment:${var.environment}"]
    }
  }
}

# ---------------------------------------------------------------------------
# GITHUB DEPLOYMENT IAM ROLE
# This role is separate from infrastructure administrator access. It can be
# assumed only by the GitHub environment specified by the trust policy.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy" {
  name               = "one-step-${var.environment}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# ---------------------------------------------------------------------------
# DEPLOYMENT PERMISSIONS
# Least-privilege permissions allow the GitHub role to upload only index.html
# and to push images to the API's ECR repository (api.tf). It cannot list the
# bucket, read objects, delete the site or images, or modify AWS
# infrastructure resources.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.site.arn}/index.html"]
  }

  # docker login to ECR. AWS does not allow this action to be limited to one
  # repository; the token alone grants nothing beyond the statement below.
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.api.arn]
  }
}

# ---------------------------------------------------------------------------
# ATTACH DEPLOYMENT PERMISSIONS
# This attaches the narrow publish-index policy to the GitHub deployment role.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "deploy" {
  name   = "publish-index"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# ROUTE 53 AVAILABILITY CHECK
# This HTTPS check contacts the CloudFront domain every 30 seconds and confirms
# that index.html contains the expected website title.
# ---------------------------------------------------------------------------
resource "aws_route53_health_check" "site" {
  fqdn              = aws_cloudfront_distribution.site.domain_name
  port              = 443
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/"
  search_string     = "One Step At A Time"
  enable_sni        = true
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "one-step-${var.environment}"
  }
}

# ---------------------------------------------------------------------------
# ALERT DELIVERY
# Email notifications are sent by SNS. The monitoring provider is explicitly
# us-east-1 because this project's SNS alarm and health-check setup uses that
# AWS region; the provider alias is configured in versions.tf.
# ---------------------------------------------------------------------------
resource "aws_sns_topic" "alerts" {
  provider = aws.monitoring
  name     = "one-step-${var.environment}-alerts"
}

# ---------------------------------------------------------------------------
# SNS EMAIL SUBSCRIPTION
# The supplied email address must accept AWS's confirmation request. Until it
# is confirmed, SNS cannot deliver availability notifications.
# ---------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "alerts" {
  provider  = aws.monitoring
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CLOUDWATCH AVAILABILITY ALARM
# The alarm turns on when the health check fails for two consecutive
# evaluation periods and clears when health is restored. Alarm and recovery
# messages are sent to the SNS topic.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "unavailable" {
  provider            = aws.monitoring
  alarm_name          = "one-step-${var.environment}-unavailable"
  alarm_description   = "The public website health check is failing."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  dimensions = {
    HealthCheckId = aws_route53_health_check.site.id
  }
}
