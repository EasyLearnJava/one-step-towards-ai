# Coding agent prompt: build a one-page AWS website project (runs on its own)

## How to use this file (for the human)

1. Start a coding agent in an **empty folder** and paste everything between `PROMPT START` and `PROMPT END`. You do not give it any values and it asks you no questions: it chooses the project's names itself, then builds and checks the whole project on your PC.
2. The agent never contacts AWS or GitHub, never commits and never pushes. At the end it reports the names it chose, every check it ran with the result, and the values only you can supply.
3. **REPLACE BEFORE DEPLOYING.** The generated docs show your private values as tokens such as `<<AWS_ACCOUNT_ID>>`, `<<GITHUB_OWNER>>` and `<<ALERT_EMAIL>>`. They are **dynamic values that must be replaced with your own original values** when you deploy; the agent never guesses them. The "Values you need" table in the generated `docs/staging-deployment.md` says where to find each one.
4. To deploy: review the files, set your git identity, commit, push, then follow `docs/staging-deployment.md`.

---

<!-- PROMPT START -->

## 1. Goal

You are a senior cloud engineer working **on your own**. In the current folder, build a complete repository that publishes **one HTML page** as a public HTTPS website on AWS:

- **Terraform**, run later by the operator from their PC, creates a private S3 bucket; a CloudFront distribution that reads it through Origin Access Control (OAC), adds five security headers and does not cache; a least-privilege IAM role that GitHub Actions assumes through OIDC (no stored AWS keys); a Route 53 HTTPS health check; a CloudWatch alarm; and an SNS email alert.
- **A separate S3 bucket for Terraform state**, created or checked by an idempotent PowerShell script.
- **GitHub Actions**: `Checks` runs on every pull request and every push to `main` (repository rules, Terraform format and validity, PowerShell parsing). `Deploy website` is started by hand; it uploads `index.html` and verifies the live page.
- **Two environments**, `staging` and `production`: the same code with different values, by default in one AWS account.
- **A repository check script** and **documentation** that a beginner can follow click by click to deploy.

There is no application server, container, database or AI service.

**This run builds the repository and verifies it locally. Deploying is done later by the operator, using the docs you write.**

## 2. How you work: on your own, no questions

1. **Never ask the human anything and never wait for input.** Make every decision yourself. Where this prompt gives a default, use it. Where it leaves a choice open, choose the simplest option that keeps the security properties in section 5, and list it under "Decisions" in your final report with a one-line reason.
2. **Follow the reference exactly.** Section 7 gives the complete, tested content of every code and configuration file. Create each file with exactly that content, replacing only the five tokens from section 4.1. Do not add, remove or reword code, settings or comments. This includes changes you consider improvements, such as stricter error handling or extra comments: the reference was tested exactly as written. If you believe something in the reference is wrong, do not change it: describe it under "Suggested fixes" in your final report.
3. **Write the docs yourself** from section 8, copying each marked block word for word.
4. **Check your work** with section 10. If a check fails, fix your files and run it again, at most three times per check. If it still fails, leave the files as they are and report the exact error.
5. **Missing tools.** If `terraform`, `git`, `bash`, `powershell.exe` or Python is not installed, do everything else, mark the checks that need it **NOT RUN** with the reason, and give the exact command for the operator. Never report a check as passed unless you ran it and saw it pass.
6. Finish with the report in section 11.

## 3. Hard rules

1. **No cloud or remote actions in this run.** Do not run `aws`, `gh`, or any `terraform` command other than `fmt`, `validate`, `version` and `init -backend=false -lockfile=readonly`. Do not run `bootstrap-state.ps1`; only parse it. Do not run `git push`, `git remote add`, `git commit` or `git config user.*`. The only network access allowed is `terraform init` downloading the AWS provider from the Terraform registry.
2. **Never invent private values.** The values in section 4.2 exist only in the operator's AWS and GitHub accounts. Never make them up, look them up, or take them from this computer (for example from `git config`, environment variables or AWS profiles). In the docs, write them exactly as the `<<NAME>>` tokens of section 4.2. Do not create `site.tfvars` or `backend.hcl`.
3. **No secrets.** Do not read `~/.aws/credentials`, `~/.aws/config`, `~/.aws/sso/cache`, environment variables such as `AWS_SECRET_ACCESS_KEY` or `AWS_SESSION_TOKEN`, or any token, password or key. The docs tell the operator never to store AWS keys in GitHub.
4. **Git.** Run `git init -b main` (or `git branch -M main` if the folder is already a repository). Leave every file uncommitted and unstaged: the commit author must be the operator's own GitHub identity, and this computer's global git identity may belong to someone else.
5. **Windows PowerShell 5.1** must run the `.ps1` script: no ternary `?:`, no `??`, no `ConvertFrom-Json -AsHashtable`, no `&&` or `||`. Save `.ps1` files as **plain ASCII**: no smart quotes or long dashes.
6. **Encoding and line endings.** Write every file as UTF-8 without a byte order mark, with LF line endings and a final newline. `scripts/check-repo.sh` must have LF endings or bash fails.
7. **Pinned versions.** Keep the GitHub Action commit SHAs, `terraform_version: 1.10.5`, the provider constraint `~> 5.0` and provider version 5.100.0 in the lock file exactly as given. Do not look up newer versions.
8. **Names.** Choose neutral names for a personal learning site. Do not use the name, brand or logo of a real company, product or person.

## 4. Values

### 4.1 Values you choose (filled into committed files)

Choose these five yourself, make them consistent with each other, and replace the tokens everywhere: in every file of section 7 and in the docs.

| Token | What it is | Rules | Example of the format |
|---|---|---|---|
| `<<PROJECT_SLUG>>` | Prefix of AWS resource names | Must match `^[a-z0-9][a-z0-9-]{1,8}[a-z0-9]$` (3 to 10 characters) and must not start with `xn--` or `sthree`. The state bucket `<<PROJECT_SLUG>>-v1-production-state-<32 hex>` is the slug length plus 53 characters and must stay within S3's limit of 63 | `cloudnotes` |
| `<<PROJECT_TAG>>` | `Project` tag on every resource, and the prefix of the state file key | lowercase letters, digits and hyphens; at most 40 characters | `cloud-learning-notes` |
| `<<SITE_TITLE>>` | The page `<title>` and `<h1>`, **and** the Route 53 health-check search string | Page text rule; at most 60 characters | `Cloud Learning Notes` |
| `<<SITE_EYEBROW>>` | Small line above the title | Page text rule; at most 60 characters | `Learning cloud deployment` |
| `<<SITE_TAGLINE>>` | Sentence under the title, the page description and the README's first line | Page text rule; at most 120 characters | `One page, delivered securely from AWS.` |

**Page text rule:** plain ASCII letters, digits, spaces and `. , : ! ? ' -` only. No `"`, `\`, `&`, `<`, `>`, `$` or `%`: these values go into Terraform strings, an HTML attribute and the health-check search string, where such characters break the syntax or change the bytes the health check looks for. The title is case-sensitive and appears exactly the same in `web/index.html` and `main.tf`.

**Other defaults:** use the region `us-east-1` everywhere, and write it directly in the docs' commands with one note that another region means replacing `us-east-1` in the site commands (the alarm and SNS topic stay in `us-east-1` in every case). Both environments use one AWS workload account; the docs mention that a separate production account is possible and needs its own one-time setup.

### 4.2 Values only the operator has

Never invent these. The docs show each one exactly as its token, in the "Values you need" table (block A in section 8), so the operator can replace it before deploying.

## 5. Security properties that must hold

The reference code in section 7 already implements all of these. They are listed so you know what must never change and what the docs explain.

- **Website bucket:** Block Public Access on, ACLs disabled (BucketOwnerEnforced), versioning on, AES256 encryption. Its policy lets only this CloudFront distribution read objects (`AWS:SourceArn`) and denies every request that is not HTTPS.
- **CloudFront:** OAC signs every origin request; HTTP redirects to HTTPS; only GET and HEAD; caching off (`Managed-CachingDisabled`); headers `Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`, `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`.
- **Deploy role:** trusted only for tokens from this repository's matching GitHub environment with audience `sts.amazonaws.com`; may only `s3:PutObject` on `index.html`.
- **Releases:** deploys run only from `main`; production deploys only a commit that already succeeded in staging.
- **State:** its own private, versioned, encrypted, HTTPS-only bucket with S3 native locking; never committed.
- **Monitoring:** health check every 30 seconds; alarm and SNS topic in `us-east-1`; missing data counts as unhealthy.

## 6. Repository layout

```text
.github/
  workflows/
    checks.yml
    deploy.yml
docs/
  operations.md
  staging-deployment.md
scripts/
  bootstrap-state.ps1
  check-repo.sh
terraform/
  site/
    .terraform.lock.hcl
    main.tf
    outputs.tf
    variables.tf
    versions.tf
  environments/
    staging/
      backend.example.hcl
      site.example.tfvars
    production/
      backend.example.hcl
      site.example.tfvars
web/
  index.html
.gitattributes
.gitignore
README.md
```

The repository root is this folder; GitHub only runs workflows from `.github/workflows` at the root. Git-ignored files the operator creates later (`site.tfvars`, `backend.hcl`, plans, state) are not part of this run.

## 7. Files (complete, tested reference)

Create every file below with exactly this content, replacing only `<<PROJECT_SLUG>>`, `<<PROJECT_TAG>>`, `<<SITE_TITLE>>`, `<<SITE_EYEBROW>>` and `<<SITE_TAGLINE>>`. No other `<<...>>` token appears in these files. The scripts were tested under Windows PowerShell 5.1 against fake AWS and Terraform commands covering every branch described below; the Terraform passed `terraform fmt -check` and `terraform validate`.

### 7.1 `.gitignore`

```gitignore
# Terraform state, saved plans and the real per-environment settings
# (site.tfvars, backend.hcl) stay on the operator's PC. Only the example files
# and the provider lock file are committed.
.terraform/
*.tfstate
*.tfstate.*
*.tfplan
*.tfvars
*.hcl
!.terraform.lock.hcl
!*.example.hcl
!*.example.tfvars
__pycache__/
.DS_Store
```

### 7.2 `.gitattributes`

```gitattributes
# Shell scripts keep LF line endings on every checkout; bash fails on CRLF.
*.sh text eol=lf
```

### 7.3 `web/index.html`

Inline CSS only: the Content Security Policy blocks scripts, images, fonts and external files. No header comment, because the page is public.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="<<SITE_TAGLINE>>">
  <title><<SITE_TITLE>></title>
  <style>
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 2rem; background: #f3f7ff; color: #172554; font-family: system-ui, sans-serif; }
    main { max-width: 46rem; text-align: center; }
    .eyebrow { color: #1d4ed8; font-size: .9rem; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; }
    h1 { margin: 1rem 0; font-size: clamp(2.5rem, 7vw, 5rem); line-height: 1.05; }
    p { color: #475569; font-size: clamp(1.1rem, 3vw, 1.4rem); line-height: 1.6; }
  </style>
</head>
<body>
  <main>
    <span class="eyebrow"><<SITE_EYEBROW>></span>
    <h1><<SITE_TITLE>></h1>
    <p><<SITE_TAGLINE>></p>
  </main>
</body>
</html>
```

### 7.4 `terraform/site/versions.tf`

```hcl
# Terraform and AWS provider versions, the S3 state backend, and two AWS
# provider configurations: one for the site's region and one fixed to us-east-1
# for monitoring.
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Partial configuration: bucket, key and region come from backend.hcl at init time.
  backend "s3" {
    # Encrypt Terraform state before storing it in the S3 state bucket.
    encrypt = true

    # S3 native state locking (needs Terraform 1.10 or later).
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "<<PROJECT_TAG>>"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Route 53 health-check metrics exist only in us-east-1, so the alarm and its SNS
# topic must live there whatever aws_region is.
provider "aws" {
  alias  = "monitoring"
  region = "us-east-1"
}
```

### 7.5 `terraform/site/variables.tf`

```hcl
# Inputs that differ per environment. Real values live in the git-ignored
# terraform/environments/<env>/site.tfvars; see the committed *.example.tfvars.
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

variable "site_bucket_name" {
  description = "Globally unique S3 bucket name for the website."
  type        = string
}

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

variable "alert_email" {
  description = "Email address for availability alerts; the SNS subscription requires confirmation."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "Provide a valid alert email address."
  }
}
```

### 7.6 `terraform/site/main.tf`

Exactly 15 managed resources and 5 data sources.

```hcl
# One environment: a private S3 bucket served by CloudFront through Origin
# Access Control with security headers, the GitHub Actions deploy role, and a
# health check whose alarm emails the operator. 15 managed resources.

# The account ID is an output, so you can confirm which account Terraform used.
data "aws_caller_identity" "current" {}

# Private website bucket. Disposable: destroy removes every object version.
resource "aws_s3_bucket" "site" {
  bucket        = var.site_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# OAC signs CloudFront's requests to S3 so the bucket never needs to be public.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "<<PROJECT_SLUG>>-${var.environment}"
  description                       = "Signed access to the private website bucket."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Five security headers on every response. The CSP allows only inline styles.
resource "aws_cloudfront_response_headers_policy" "site" {
  name = "<<PROJECT_SLUG>>-${var.environment}-security"

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

# Caching is off so a new upload is visible immediately.
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "<<SITE_TITLE>> - ${var.environment}"

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

  # Default *.cloudfront.net certificate; no custom domain in this project.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Only this distribution may read objects, and only over HTTPS.
data "aws_iam_policy_document" "site_bucket" {
  statement {
    sid       = "AllowOnlyThisCloudFrontDistribution"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]
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

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_bucket.json
}

# GitHub OIDC trust: only this repository's matching GitHub environment, audience sts.amazonaws.com.
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

resource "aws_iam_role" "deploy" {
  name               = "<<PROJECT_SLUG>>-${var.environment}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust.json
}

# Least privilege: the deploy role may only upload index.html.
data "aws_iam_policy_document" "deploy" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.site.arn}/index.html"]
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "publish-index"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# Fetches the page over HTTPS every 30 s and requires the page title in the body.
resource "aws_route53_health_check" "site" {
  fqdn              = aws_cloudfront_distribution.site.domain_name
  port              = 443
  type              = "HTTPS_STR_MATCH"
  resource_path     = "/"
  search_string     = "<<SITE_TITLE>>"
  enable_sni        = true
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "<<PROJECT_SLUG>>-${var.environment}"
  }
}

resource "aws_sns_topic" "alerts" {
  provider = aws.monitoring
  name     = "<<PROJECT_SLUG>>-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "alerts" {
  provider  = aws.monitoring
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ALARM after 2 failing minutes (or no data); OK when healthy again. Both send email.
resource "aws_cloudwatch_metric_alarm" "unavailable" {
  provider            = aws.monitoring
  alarm_name          = "<<PROJECT_SLUG>>-${var.environment}-unavailable"
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
```

### 7.7 `terraform/site/outputs.tf`

```hcl
# After apply, website_url, site_bucket_name and deploy_role_arn are copied into
# the GitHub environment variables WEBSITE_URL, SITE_BUCKET and AWS_ROLE_ARN.
output "website_url" {
  description = "HTTPS address of the website."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "site_bucket_name" {
  value = aws_s3_bucket.site.id
}

output "deploy_role_arn" {
  value = aws_iam_role.deploy.arn
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

### 7.8 `terraform/site/.terraform.lock.hcl`

Create this file exactly; do not generate or regenerate it. It pins AWS provider 5.100.0 with checksums for every platform (`zh:` lines) and for several common ones (`h1:` lines). `terraform init -backend=false -lockfile=readonly` (section 10) verifies the downloaded provider against it. If that command prints the warning "Provider lock file not updated", that is harmless: it only means your platform's `h1:` checksum is not recorded. Leave the file unchanged.

```hcl
# This file is maintained automatically by "terraform init".
# Manual edits may be lost in future updates.

provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.100.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:H3mU/7URhP0uCRGK8jeQRKxx2XFzEqLiOq/L2Bbiaxs=",
    "h1:Ijt7pOlB7Tr7maGQIqtsLFbl7pSMIj06TVdkoSBcYOw=",
    "h1:edXOJWE4ORX8Fm+dpVpICzMZJat4AX0VRCAy/xkcOc0=",
    "h1:lcDxx0Nx+ifFqTBpxz8Un27O0s+I7UNJAr/rUpSqlig=",
    "zh:054b8dd49f0549c9a7cc27d159e45327b7b65cf404da5e5a20da154b90b8a644",
    "zh:0b97bf8d5e03d15d83cc40b0530a1f84b459354939ba6f135a0086c20ebbe6b2",
    "zh:1589a2266af699cbd5d80737a0fe02e54ec9cf2ca54e7e00ac51c7359056f274",
    "zh:6330766f1d85f01ae6ea90d1b214b8b74cc8c1badc4696b165b36ddd4cc15f7b",
    "zh:7c8c2e30d8e55291b86fcb64bdf6c25489d538688545eb48fd74ad622e5d3862",
    "zh:99b1003bd9bd32ee323544da897148f46a527f622dc3971af63ea3e251596342",
    "zh:9b12af85486a96aedd8d7984b0ff811a4b42e3d88dad1a3fb4c0b580d04fa425",
    "zh:9f8b909d3ec50ade83c8062290378b1ec553edef6a447c56dadc01a99f4eaa93",
    "zh:aaef921ff9aabaf8b1869a86d692ebd24fbd4e12c21205034bb679b9caf883a2",
    "zh:ac882313207aba00dd5a76dbd572a0ddc818bb9cbf5c9d61b28fe30efaec951e",
    "zh:bb64e8aff37becab373a1a0cc1080990785304141af42ed6aa3dd4913b000421",
    "zh:dfe495f6621df5540d9c92ad40b8067376350b005c637ea6efac5dc15028add4",
    "zh:f0ddf0eaf052766cfe09dea8200a946519f653c384ab4336e2a4a64fdd6310e9",
    "zh:f1b7e684f4c7ae1eed272b6de7d2049bb87a0275cb04dbb7cda6636f600699c9",
    "zh:ff461571e3f233699bf690db319dfe46aec75e58726636a0d97dd9ac6e32fb70",
  ]
}
```

### 7.9 Environment example files

These are committed and hold only obviously fake values. The operator copies them to the git-ignored `site.tfvars` and `backend.hcl` later.

`terraform/environments/staging/backend.example.hcl`:

```hcl
# scripts/bootstrap-state.ps1 normally writes backend.hcl (git-ignored) for you.
# Copy this file to backend.hcl only if you already have an approved state
# bucket, and replace the bucket name.
bucket = "replace-with-private-state-bucket"
key    = "<<PROJECT_TAG>>/staging/terraform.tfstate"
region = "us-east-1"
```

`terraform/environments/staging/site.example.tfvars`:

```hcl
# Copy to site.tfvars (git-ignored) and replace every value below.
# github_repository must match GitHub's OIDC subject exactly, usually the ID form
#   owner@ownerId/repo@repoId.
# github_oidc_provider_arn is the oidc-provider ARN in THIS account
#   (IAM > Identity providers), not the deploy role ARN.
# alert_email must be a real mailbox; confirm the SNS subscription from it.

aws_region               = "us-east-1"
environment              = "staging"
site_bucket_name         = "replace-with-globally-unique-staging-bucket"
github_repository        = "replace-owner/replace-repository"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
alert_email              = "replace@example.com"
```

`terraform/environments/production/backend.example.hcl`:

```hcl
# scripts/bootstrap-state.ps1 normally writes backend.hcl (git-ignored) for you.
# Copy this file to backend.hcl only if you already have an approved state
# bucket, and replace the bucket name.
bucket = "replace-with-private-state-bucket"
key    = "<<PROJECT_TAG>>/production/terraform.tfstate"
region = "us-east-1"
```

`terraform/environments/production/site.example.tfvars`:

```hcl
# Copy to site.tfvars (git-ignored) and replace every value below.
# github_repository must match GitHub's OIDC subject exactly, usually the ID form
#   owner@ownerId/repo@repoId.
# github_oidc_provider_arn is the oidc-provider ARN in THIS account
#   (IAM > Identity providers), not the deploy role ARN.
# alert_email must be a real mailbox; confirm the SNS subscription from it.
# Production needs its own bucket name; it may share the account with staging.

aws_region               = "us-east-1"
environment              = "production"
site_bucket_name         = "replace-with-globally-unique-production-bucket"
github_repository        = "replace-owner/replace-repository"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
alert_email              = "replace@example.com"
```

### 7.10 `.github/workflows/checks.yml`

Two jobs. `validate` (Ubuntu) runs the repository rules, then Terraform format, init without state and validate. `scripts` (Windows) parses every `.ps1` file with Windows PowerShell 5.1. Neither touches AWS.

```yaml
# Runs on every pull request and every push to main. Checks the repository
# rules (scripts/check-repo.sh), Terraform formatting and validity, and that the
# PowerShell scripts parse in Windows PowerShell 5.1. It never contacts AWS.
name: Checks

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Check repository rules
        run: bash scripts/check-repo.sh
      - uses: hashicorp/setup-terraform@b9cd54a3c349d3f38e8881555d616ced269862dd # v3.1.2
        with:
          terraform_version: 1.10.5
      - name: Check formatting
        run: terraform fmt -check -recursive terraform
      - name: Initialize without accessing state
        working-directory: terraform/site
        run: terraform init -backend=false -lockfile=readonly
      - name: Validate infrastructure
        working-directory: terraform/site
        run: terraform validate

  scripts:
    runs-on: windows-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Parse scripts with Windows PowerShell 5.1
        shell: powershell
        run: |
          $failed = $false
          foreach ($file in Get-ChildItem -Path scripts -Filter *.ps1) {
            $tokens = $null
            $parseErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            foreach ($parseError in $parseErrors) {
              Write-Host "$($file.Name):$($parseError.Extent.StartLineNumber): $($parseError.Message)"
              $failed = $true
            }
          }
          if ($failed) { exit 1 }
          Write-Host "All scripts parse in Windows PowerShell $($PSVersionTable.PSVersion)."
```

### 7.11 `.github/workflows/deploy.yml`

```yaml
# Manual release. Uploads web/index.html to the chosen environment through the
# OIDC deploy role (no stored AWS keys), then checks that the live page matches
# byte for byte. Production first requires a successful staging deployment of
# the same commit.
name: Deploy website

on:
  workflow_dispatch:
    inputs:
      environment:
        description: "Deploy the selected main-branch commit to this environment"
        required: true
        type: choice
        options:
          - staging
          - production

permissions:
  contents: read
  deployments: read
  id-token: write

concurrency:
  group: website-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  deploy:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    timeout-minutes: 15
    environment: ${{ inputs.environment }}
    env:
      AWS_REGION: ${{ vars.AWS_REGION }}
      SITE_BUCKET: ${{ vars.SITE_BUCKET }}
      WEBSITE_URL: ${{ vars.WEBSITE_URL }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Require this commit to have passed staging
        if: inputs.environment == 'production'
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          set -euo pipefail
          deployments="$(gh api "repos/${GITHUB_REPOSITORY}/deployments?environment=staging&sha=${GITHUB_SHA}&per_page=100" --jq '.[].id')"
          for id in $deployments; do
            status="$(gh api "repos/${GITHUB_REPOSITORY}/deployments/${id}/statuses" --jq '.[0].state')"
            if [ "$status" = "success" ]; then
              echo "Staging deployment ${id} succeeded for ${GITHUB_SHA}."
              exit 0
            fi
          done
          echo "No successful staging deployment found for ${GITHUB_SHA}." >&2
          exit 1
      - name: Configure AWS credentials with OIDC
        uses: aws-actions/configure-aws-credentials@7474bc4690e29a8392af63c5b98e7449536d5c3a # v4.3.1
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Publish HTML
        run: |
          set -euo pipefail
          aws s3api put-object \
            --bucket "$SITE_BUCKET" \
            --key index.html \
            --body web/index.html \
            --content-type 'text/html; charset=utf-8' \
            --cache-control 'no-cache' \
            --metadata "commit=${GITHUB_SHA}" > /dev/null
      - name: Verify the public page matches this release
        run: |
          set -euo pipefail
          for attempt in $(seq 1 12); do
            if curl --fail --silent --show-error --max-time 15 "${WEBSITE_URL}/" -o /tmp/deployed-index.html \
               && cmp -s web/index.html /tmp/deployed-index.html; then
              echo "Verified release ${GITHUB_SHA} at ${WEBSITE_URL}"
              exit 0
            fi
            echo "Page not yet verified; retry ${attempt}/12."
            sleep 10
          done
          echo "Deployment verification failed." >&2
          exit 1
```

### 7.12 `scripts/bootstrap-state.ps1`

Creates **or checks** the state bucket for one environment:

| It finds | It does | Asks for confirmation? |
|---|---|---|
| The AWS CLI is signed in to a different account than `-ExpectedAccountId` | Stops; no AWS change | No |
| No `backend.hcl` | Creates `<<PROJECT_SLUG>>-v1-<env>-state-<32 hex>`; turns on block public access, versioning and AES256; adds the HTTPS-only policy; reads every setting back; then writes `backend.hcl`, refusing to overwrite one | Yes, once |
| `backend.hcl` exists and the bucket is fully set up | Prints every check as `[OK]` and "Nothing was changed" | No |
| `backend.hcl` exists and settings are missing | Prints them as `[MISSING]`, fixes only those (other bucket-policy statements are kept), then verifies again | Yes |
| `backend.hcl` names a bucket that is missing, in another account or in another region, has an invalid name, or checking the state file fails with anything but "not found" | Stops with what to fix; no AWS change | No |

It never creates a second bucket for an environment, never rewrites `backend.hcl`, never deletes anything, and supports `-WhatIf`.

```powershell
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "High")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("staging", "production")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[a-z0-9-]+$")]
    [string]$Region,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9]{12}$")]
    [string]$ExpectedAccountId
)

# Creates or checks the Terraform state bucket for one environment.
#   - No backend.hcl: creates a new private, versioned, encrypted, HTTPS-only
#     bucket, verifies it, then writes backend.hcl.
#   - backend.hcl present: reads the bucket it names, reports each setting as
#     already applied or missing, and applies only what is missing after you
#     confirm. Nothing is changed when everything is already applied.
# It never creates a second bucket for an environment and never rewrites an
# existing backend.hcl. -WhatIf shows what would happen without changing AWS.

$ErrorActionPreference = "Stop"
$Environment = $Environment.ToLowerInvariant()
$Region = $Region.ToLowerInvariant()
$projectRoot = Split-Path -Parent $PSScriptRoot
# Nested Join-Path keeps the path valid on Windows and in PowerShell 7 elsewhere.
$backendPath = Join-Path $projectRoot (Join-Path "terraform" (Join-Path "environments" (Join-Path $Environment "backend.hcl")))
$defaultKey = "<<PROJECT_TAG>>/$Environment/terraform.tfstate"
$ownerArgs = @("--expected-bucket-owner", $ExpectedAccountId)

function Invoke-AwsRaw {
    # Runs the AWS CLI and returns its exit code and output without throwing, so
    # expected answers such as "no bucket policy" can be handled. Windows
    # PowerShell 5.1 turns redirected stderr into a terminating error under
    # "Stop", so this function uses "Continue" for its own scope only.
    # On success Text is stdout only, so a CLI warning on stderr cannot break
    # the JSON; on failure it is stderr followed by stdout.
    param([string[]]$Arguments)

    $ErrorActionPreference = "Continue"
    $output = & aws @Arguments --region $Region --output json --no-cli-pager 2>&1
    $code = $LASTEXITCODE
    # "$_" turns stderr records into text and copes with no output at all.
    $stdout = @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $stderr = @($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $text = $stdout -join [Environment]::NewLine
    if ($code -ne 0) { $text = ($stderr + $stdout) -join [Environment]::NewLine }
    return [pscustomobject]@{ ExitCode = $code; Text = $text }
}

function Invoke-Aws {
    param([string[]]$Arguments)

    $result = Invoke-AwsRaw $Arguments
    if ($result.ExitCode -ne 0) {
        throw "AWS CLI failed (exit $($result.ExitCode)): $($result.Text)"
    }
    return $result.Text
}

function Read-BackendFile {
    # Reads bucket, key and region from backend.hcl; comment lines are ignored.
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*(bucket|key|region)\s*=\s*"([^"]*)"\s*$') {
            $values[$Matches[1]] = $Matches[2]
        }
    }
    return $values
}

function Get-BucketRegion {
    param([string]$Bucket)

    $location = (Invoke-Aws (@("s3api", "get-bucket-location", "--bucket", $Bucket) + $ownerArgs)) | ConvertFrom-Json
    $actual = $location.LocationConstraint
    if (-not $actual) { $actual = "us-east-1" }
    return $actual
}

function Test-TlsOnlyPolicy {
    # True when the policy has a Deny for all principals and all S3 actions on
    # the bucket and its objects whenever aws:SecureTransport is false. Any
    # extra condition would narrow the Deny, so aws:SecureTransport must be its
    # only condition.
    param($Policy, [string]$Bucket)

    $needed = @("arn:aws:s3:::$Bucket", "arn:aws:s3:::$Bucket/*")
    foreach ($statement in @($Policy.Statement)) {
        if ($statement.Effect -ne "Deny") { continue }
        $allPrincipals = ($statement.Principal -eq "*") -or ($statement.Principal.AWS -eq "*")
        $secure = $null
        if ($statement.Condition -and $statement.Condition.Bool -and
            @($statement.Condition.PSObject.Properties).Count -eq 1 -and
            @($statement.Condition.Bool.PSObject.Properties).Count -eq 1) {
            $secure = $statement.Condition.Bool."aws:SecureTransport"
        }
        $resources = @($statement.Resource)
        $missingResources = @($needed | Where-Object { $_ -notin $resources })
        if ($allPrincipals -and (@($statement.Action) -contains "s3:*") -and ("$secure" -eq "false") -and $missingResources.Count -eq 0) {
            return $true
        }
    }
    return $false
}

function Get-BucketState {
    # Reads the four settings this script manages. "Not configured" answers
    # from S3 count as missing; any other error stops the script.
    param([string]$Bucket)

    $state = [pscustomobject]@{
        PublicAccessBlocked = $false
        VersioningEnabled   = $false
        Encryption          = $null
        Policy              = $null
        TlsOnly             = $false
    }

    $result = Invoke-AwsRaw (@("s3api", "get-public-access-block", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $block = ($result.Text | ConvertFrom-Json).PublicAccessBlockConfiguration
        $state.PublicAccessBlocked = [bool]($block.BlockPublicAcls -and $block.IgnorePublicAcls -and $block.BlockPublicPolicy -and $block.RestrictPublicBuckets)
    } elseif ($result.Text -notmatch "NoSuchPublicAccessBlockConfiguration") {
        throw "Could not read the public access block of ${Bucket}: $($result.Text)"
    }

    $versioning = Invoke-Aws (@("s3api", "get-bucket-versioning", "--bucket", $Bucket) + $ownerArgs)
    # The output is empty when versioning has never been enabled.
    if ($versioning.Trim()) {
        $state.VersioningEnabled = (($versioning | ConvertFrom-Json).Status -eq "Enabled")
    }

    $result = Invoke-AwsRaw (@("s3api", "get-bucket-encryption", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $rules = @(($result.Text | ConvertFrom-Json).ServerSideEncryptionConfiguration.Rules)
        $algorithms = @($rules | ForEach-Object { $_.ApplyServerSideEncryptionByDefault.SSEAlgorithm } | Where-Object { $_ })
        if ($algorithms.Count -gt 0) { $state.Encryption = $algorithms[0] }
    } elseif ($result.Text -notmatch "ServerSideEncryptionConfigurationNotFoundError") {
        throw "Could not read the encryption of ${Bucket}: $($result.Text)"
    }

    $result = Invoke-AwsRaw (@("s3api", "get-bucket-policy", "--bucket", $Bucket) + $ownerArgs)
    if ($result.ExitCode -eq 0) {
        $state.Policy = ($result.Text | ConvertFrom-Json).Policy | ConvertFrom-Json
        $state.TlsOnly = Test-TlsOnlyPolicy $state.Policy $Bucket
    } elseif ($result.Text -notmatch "NoSuchBucketPolicy") {
        throw "Could not read the bucket policy of ${Bucket}: $($result.Text)"
    }

    return $state
}

function Show-BucketState {
    # Prints one line per setting and returns the names of missing settings.
    param($State)

    $encryptionLabel = "Default encryption"
    if ($State.Encryption) { $encryptionLabel = "Default encryption ($($State.Encryption))" }
    $checks = @(
        @("Public access block (all four settings on)", $State.PublicAccessBlocked),
        @("Versioning enabled", $State.VersioningEnabled),
        @($encryptionLabel, [bool]$State.Encryption),
        @("HTTPS-only bucket policy", $State.TlsOnly)
    )
    $missing = @()
    foreach ($check in $checks) {
        if ($check[1]) {
            Write-Host "[OK]      $($check[0]): already applied"
        } else {
            Write-Host "[MISSING] $($check[0])"
            $missing += $check[0]
        }
    }
    return $missing
}

function Set-BucketSettings {
    # Applies only the settings that $State reports as missing. An existing
    # bucket policy keeps all its other statements; only the HTTPS-only
    # statement is added or replaced.
    param([string]$Bucket, $State)

    if (-not $State.PublicAccessBlocked) {
        $null = Invoke-Aws (@(
            "s3api", "put-public-access-block", "--bucket", $Bucket,
            "--public-access-block-configuration",
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
        ) + $ownerArgs)
        Write-Host "Applied: public access block"
    }
    if (-not $State.VersioningEnabled) {
        $null = Invoke-Aws (@("s3api", "put-bucket-versioning", "--bucket", $Bucket, "--versioning-configuration", "Status=Enabled") + $ownerArgs)
        Write-Host "Applied: versioning"
    }
    if (-not $State.Encryption) {
        $null = Invoke-Aws (@(
            "s3api", "put-bucket-encryption", "--bucket", $Bucket,
            "--server-side-encryption-configuration",
            "Rules=[{ApplyServerSideEncryptionByDefault={SSEAlgorithm=AES256}}]"
        ) + $ownerArgs)
        Write-Host "Applied: default encryption (AES256)"
    }
    if (-not $State.TlsOnly) {
        $tlsStatement = [pscustomobject][ordered]@{
            Sid       = "DenyInsecureTransport"
            Effect    = "Deny"
            Principal = "*"
            Action    = "s3:*"
            Resource  = @("arn:aws:s3:::$Bucket", "arn:aws:s3:::$Bucket/*")
            Condition = @{ Bool = @{ "aws:SecureTransport" = "false" } }
        }
        $version = "2012-10-17"
        $statements = @()
        if ($State.Policy) {
            if ($State.Policy.Version) { $version = $State.Policy.Version }
            $statements = @(@($State.Policy.Statement) | Where-Object { $_.Sid -ne "DenyInsecureTransport" })
        }
        $policy = [ordered]@{ Version = $version; Statement = @($statements) + @($tlsStatement) } | ConvertTo-Json -Depth 20 -Compress
        $policyFile = Join-Path ([System.IO.Path]::GetTempPath()) ("tf-state-policy-" + [Guid]::NewGuid().ToString("N") + ".json")
        try {
            [System.IO.File]::WriteAllText($policyFile, $policy, (New-Object System.Text.UTF8Encoding($false)))
            $null = Invoke-Aws (@("s3api", "put-bucket-policy", "--bucket", $Bucket, "--policy", "file://$policyFile") + $ownerArgs)
        } finally {
            if (Test-Path -LiteralPath $policyFile) { Remove-Item -LiteralPath $policyFile -ErrorAction Stop }
        }
        Write-Host "Applied: HTTPS-only bucket policy"
    }
}

function Assert-BucketReady {
    # Reads every setting back from AWS and stops if any is still missing.
    param([string]$Bucket)

    $actualRegion = Get-BucketRegion $Bucket
    if ($actualRegion -ne $Region) { throw "Bucket region verification failed: expected $Region, got $actualRegion." }
    $state = Get-BucketState $Bucket
    $failed = @()
    if (-not $state.PublicAccessBlocked) { $failed += "public access block" }
    if (-not $state.VersioningEnabled) { $failed += "versioning" }
    if (-not $state.Encryption) { $failed += "default encryption" }
    if (-not $state.TlsOnly) { $failed += "HTTPS-only bucket policy" }
    if ($failed.Count -gt 0) { throw "Verification failed for bucket ${Bucket}: $($failed -join ', ')." }
}

# --- Step 1: the AWS CLI must use the intended account -----------------------
$identity = (Invoke-Aws @("sts", "get-caller-identity")) | ConvertFrom-Json
if ($identity.Account -ne $ExpectedAccountId) {
    throw "Current AWS account does not match ExpectedAccountId. No AWS change was made."
}
Write-Host "[OK]      AWS CLI account matches ExpectedAccountId"

# --- Step 2a: backend.hcl exists, so check its bucket instead of creating one -
if (Test-Path -LiteralPath $backendPath) {
    Write-Host "Found $backendPath; checking the bucket it names. No new bucket will be created."
    $backend = Read-BackendFile $backendPath
    $bucket = $backend["bucket"]
    if (-not $bucket) {
        throw "backend.hcl has no bucket = `"...`" line. Fix the file; no AWS change was made."
    }
    if ($bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') {
        throw "backend.hcl bucket '$bucket' is not a valid S3 bucket name. Fix the file; no AWS change was made."
    }
    if ($backend["region"] -and $backend["region"] -ne $Region) {
        throw "backend.hcl uses region $($backend["region"]) but -Region is $Region. Run again with -Region $($backend["region"]); no AWS change was made."
    }

    $head = Invoke-AwsRaw (@("s3api", "head-bucket", "--bucket", $bucket) + $ownerArgs)
    if ($head.ExitCode -ne 0) {
        throw "Bucket $bucket named in backend.hcl was not found in account $ExpectedAccountId, or you cannot access it. Check the name in backend.hcl; to create a new bucket instead, move backend.hcl aside first. No AWS change was made. Details: $($head.Text)"
    }
    Write-Host "[OK]      Bucket $bucket exists and belongs to account $ExpectedAccountId"

    $actualRegion = Get-BucketRegion $bucket
    if ($actualRegion -ne $Region) {
        throw "Bucket $bucket is in $actualRegion, not $Region. Fix backend.hcl and -Region; no AWS change was made."
    }
    Write-Host "[OK]      Bucket region is $Region"

    $key = $backend["key"]
    if (-not $key) { $key = $defaultKey }
    if ($key -ne $defaultKey) {
        Write-Host "[INFO]    backend.hcl uses key $key (default would be $defaultKey); keeping it."
    }
    # Only "not found" means there is no state yet; any other error (for example
    # access denied) stops the script instead of being reported as "no state".
    $object = Invoke-AwsRaw (@("s3api", "head-object", "--bucket", $bucket, "--key", $key) + $ownerArgs)
    if ($object.ExitCode -eq 0) {
        Write-Host "[INFO]    Terraform state file found at $key"
    } elseif ($object.Text -match '\((404|NoSuchKey|NotFound)\)') {
        Write-Host "[INFO]    No Terraform state file at $key yet (normal before the first apply)"
    } else {
        throw "Could not check the Terraform state file at ${key}. No AWS change was made. Details: $($object.Text)"
    }

    $state = Get-BucketState $bucket
    $missing = @(Show-BucketState $state)
    if ($missing.Count -eq 0) {
        Write-Host "Everything is already applied. Nothing was changed; backend.hcl was left as it is."
        return
    }
    if (-not $PSCmdlet.ShouldProcess("bucket $bucket in account $ExpectedAccountId", "Apply missing settings: $($missing -join '; ')")) {
        return
    }
    Set-BucketSettings $bucket $state
    Assert-BucketReady $bucket
    Write-Host "Applied the missing settings and verified bucket $bucket. backend.hcl was left as it is."
    return
}

# --- Step 2b: no backend.hcl, so create a new bucket and write backend.hcl ----
# A fresh random name avoids taking over or changing a pre-existing bucket.
$bucket = "<<PROJECT_SLUG>>-v1-$Environment-state-$([Guid]::NewGuid().ToString('N'))"
if (-not $PSCmdlet.ShouldProcess("AWS account $ExpectedAccountId, region $Region", "Create state bucket $bucket for $Environment")) {
    return
}

$creationAttempted = $false
try {
    $createArguments = @("s3api", "create-bucket", "--bucket", $bucket)
    if ($Region -ne "us-east-1") {
        $createArguments += @("--create-bucket-configuration", "LocationConstraint=$Region")
    }
    $creationAttempted = $true
    $null = Invoke-Aws $createArguments

    # A new bucket is treated as having nothing applied, so every setting is set explicitly.
    $fresh = [pscustomobject]@{ PublicAccessBlocked = $false; VersioningEnabled = $false; Encryption = $null; Policy = $null; TlsOnly = $false }
    Set-BucketSettings $bucket $fresh
    Assert-BucketReady $bucket

    $backendText = "bucket = `"$bucket`"`nkey    = `"$defaultKey`"`nregion = `"$Region`"`n"
    # CreateNew refuses to overwrite a backend created by another process.
    $file = [System.IO.File]::Open($backendPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $writer = New-Object System.IO.StreamWriter($file, (New-Object System.Text.UTF8Encoding($false)))
        try { $writer.Write($backendText) } finally { $writer.Dispose() }
    } finally {
        $file.Dispose()
    }
    Write-Host "Created and verified state bucket: $bucket"
    Write-Host "Created backend configuration: $backendPath"
    Write-Host "The bucket is separate from the website and must be reviewed separately during teardown."
} catch {
    if ($creationAttempted) {
        throw "Bootstrap did not finish. Bucket $bucket may still exist in account $ExpectedAccountId and region $Region. Inspect it and its backend file before retrying. Original error: $($_.Exception.Message)"
    }
    throw
}
```

### 7.13 `scripts/check-repo.sh`

Repository rules for CI and for local use. It checks that the health-check text is the page title, that code has no unfilled tokens, that no account IDs or GitHub ID pairs are present, that the scripts are ASCII, and that the local-only files are ignored.

```bash
#!/usr/bin/env bash
# Repository rules that need no cloud access. The Checks workflow runs this on
# every pull request and push to main; run it locally from the repository root
# with "bash scripts/check-repo.sh" (Git Bash on Windows). It searches tracked
# files and new files that are not git-ignored, so it also works before the
# first commit.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

failed=0
pass() { echo "[OK]   $1"; }
fail() { echo "[FAIL] $1"; failed=1; }

# git grep exits 1 when nothing matches; that is the passing case here.
search() {
  git grep --untracked -n -I -E "$@" || {
    status=$?
    [ "$status" -eq 1 ] || return "$status"
  }
}

# 1. The Route 53 health check looks for search_string in the first 5,120 bytes
#    of the page. It must be the page title, or the alarm fires on a good page.
title="$(sed -n 's/^[[:space:]]*search_string[[:space:]]*=[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' terraform/site/main.tf)"
first_bytes="$(head -c 5120 web/index.html)"
if [ -z "$title" ]; then
  fail "No search_string found in terraform/site/main.tf"
else
  case "$first_bytes" in
    *"<title>${title}</title>"*) pass "Health-check text \"${title}\" is the page title within the first 5,120 bytes" ;;
    *) fail "web/index.html must contain <title>${title}</title> within its first 5,120 bytes" ;;
  esac
fi

# 2. Code and configuration must not keep unfilled placeholders (upper-case
#    names in double angle brackets). Docs may keep them for values only the
#    operator knows.
hits="$(search '<<[A-Z_]+>>' -- terraform web scripts .github)"
if [ -n "$hits" ]; then
  fail "Unfilled placeholders in code or configuration:"
  echo "$hits"
else
  pass "No unfilled placeholders in code or configuration"
fi

# 3. No real AWS account IDs. 123456789012 is AWS's documentation example. The
#    provider lock file holds checksums, not IDs. Twelve digits next to a
#    letter, + or / are part of longer text such as a base64 image, not an ID.
hits="$(search '(^|[^0-9A-Za-z+/])[0-9]{12}([^0-9A-Za-z+/]|$)' -- . ':!*.terraform.lock.hcl')"
if [ -n "$hits" ]; then
  hits="$(printf '%s\n' "$hits" | grep -v '123456789012' || [ "$?" -eq 1 ])"
fi
if [ -n "$hits" ]; then
  fail "Possible AWS account IDs (12 digits) committed:"
  echo "$hits"
else
  pass "No AWS account IDs other than the documentation example"
fi

# 4. No GitHub ID-form repository names (owner@ownerId/repo@repoId).
hits="$(search '@[0-9]{3,}/' -- .)"
if [ -n "$hits" ]; then
  fail "GitHub owner or repository IDs committed:"
  echo "$hits"
else
  pass "No GitHub owner or repository IDs"
fi

# 5. Windows PowerShell 5.1 misreads non-ASCII characters in UTF-8 files
#    without a byte order mark, so the scripts must be plain ASCII.
hits="$(LC_ALL=C grep -Hn "$(printf '[\200-\377]')" scripts/*.ps1 || { status=$?; [ "$status" -eq 1 ] || exit "$status"; })"
if [ -n "$hits" ]; then
  fail "Non-ASCII characters in PowerShell scripts:"
  echo "$hits"
else
  pass "PowerShell scripts are plain ASCII"
fi

# 6. Real settings, state and plans must stay out of Git; the lock file and the
#    examples must stay in.
ignore_ok=1
for path in \
  terraform/environments/staging/site.tfvars terraform/environments/staging/backend.hcl \
  terraform/environments/production/site.tfvars terraform/environments/production/backend.hcl \
  terraform/site/terraform.tfstate terraform/site/staging.tfplan; do
  if ! git check-ignore -q "$path"; then
    fail "$path is not git-ignored"
    ignore_ok=0
  fi
done
for path in \
  terraform/site/.terraform.lock.hcl \
  terraform/environments/staging/site.example.tfvars terraform/environments/staging/backend.example.hcl \
  terraform/environments/production/site.example.tfvars terraform/environments/production/backend.example.hcl; do
  if git check-ignore -q "$path"; then
    fail "$path must not be git-ignored"
    ignore_ok=0
  fi
done
if [ "$ignore_ok" -eq 1 ]; then
  pass "Local-only files are ignored; the lock file and examples are not"
fi

if [ "$failed" -ne 0 ]; then
  echo "Repository checks failed." >&2
  exit 1
fi
echo "All repository checks passed."
```

## 8. Documentation

Write plain, friendly Markdown for a beginner. Use the five values you chose and `us-east-1` directly; write every section 4.2 value as its token. Copy blocks A to G **word for word** (they sit between `BLOCK ... START` and `BLOCK ... END` lines; copy what is between the lines, not the marker lines), replacing only the five section 4.1 tokens inside them. Never paraphrase an error message, a console path, an action list or an expected output.

### 8.1 `README.md`

1. `# <<SITE_TITLE>>`, then `<<SITE_TAGLINE>>` on its own line.
2. "What this is": one HTML page published over HTTPS from a private S3 bucket through CloudFront; no server, container or database.
3. Architecture as a text block:

   ```text
   Browser --HTTPS--> CloudFront --signed request (OAC)--> private S3 bucket (index.html)
   Route 53 health check --> CloudWatch alarm (us-east-1) --> SNS email
   GitHub Actions --OIDC, no stored keys--> deploy role: may only upload index.html
   Terraform state --> its own private S3 bucket
   ```

4. The layout from section 6, one line per file saying what it is for.
5. "Checks": what `Checks` runs (repository rules, Terraform format and validity, script parsing in Windows PowerShell 5.1), and a link to "Running the checks locally" in `docs/operations.md`. Do not list the check commands in the README.
6. "Security boundaries": everything in `web/` is public; no credentials in the repository; Terraform runs with the operator's own AWS identity while deploys use the restricted OIDC role; production needs GitHub approval and a commit that passed staging; never commit `site.tfvars`, `backend.hcl`, state or plans.
7. "Cost": about $2 to $6 per month per environment, mostly the Route 53 health check's HTTPS and text-matching features; check current AWS prices.
8. "Start here": link `docs/staging-deployment.md` (first deployment) and `docs/operations.md` (production, operations, teardown).

### 8.2 `docs/staging-deployment.md` (click-by-click first deployment)

Sections in this order:

1. **What you will build**: the page, the URL form `https://<random>.cloudfront.net`, the cost line from the README, and that every step that changes AWS or GitHub is done by you.
2. **Values you need**: block A.
3. **One-time setup (check before you redo it)**: block B, then block C.
4. **Create the state bucket**: from the repository root in a PowerShell window, `.\scripts\bootstrap-state.ps1 -Environment staging -Region us-east-1 -ExpectedAccountId "<<AWS_ACCOUNT_ID>>" -WhatIf`, then the same command without `-WhatIf`, answering `Y`. Show the expected output from block D. Say that if `backend.hcl` already exists the script only checks the bucket, and that the operator can also copy `backend.example.hcl` to `backend.hcl` for an existing approved bucket and then run the script with `-WhatIf` to check it.
5. **Configure and create staging**: `Copy-Item .\terraform\environments\staging\site.example.tfvars .\terraform\environments\staging\site.tfvars` (only if it does not exist), fill in every value from block A, then:

   ```powershell
   Set-Location .\terraform\site
   terraform init -reconfigure "-backend-config=..\environments\staging\backend.hcl"
   terraform plan "-var-file=..\environments\staging\site.tfvars" "-out=staging.tfplan"
   terraform apply staging.tfplan
   terraform output
   ```

   Explain each command in one line and show the expected output from block D. Say that a saved plan can be applied only once, that CloudFront takes several minutes, and that 403 and an alarm are normal until the first deploy.
6. **Publish with GitHub**: set the repo-local identity (`git config --local user.name "<<GIT_AUTHOR_NAME>>"`, `git config --local user.email "<<GIT_AUTHOR_EMAIL>>"`), stage files by path (never `git add -A`), commit, `git remote add origin https://github.com/<<GITHUB_OWNER>>/<<GITHUB_REPO>>.git`, `git push -u origin main`; wait for a green `Checks` run; create the `staging` environment and its four variables (block A); run **Actions > Deploy website > Run workflow**, branch `main`, environment `staging`; confirm the SNS email ("AWS Notification - Subscription Confirmation", "Confirm subscription").
7. **Check the deployment**: block F.
8. **Troubleshooting**: block E.

### 8.3 `docs/operations.md`

1. **Prerequisites**: a short summary that links to block B in the staging guide.
2. **Staging**: the commands from the staging guide, without the explanations.
3. **Production**: create the `production` environment (branch rule `main`, required reviewers where the plan allows) and its four variables **before** the first production run; run the bootstrap with `-Environment production`; create `production\site.tfvars` with `<<SITE_BUCKET_NAME_PRODUCTION>>`; `terraform init -reconfigure` with the production backend; in the plan check that the deploy role's trust `sub` ends in `:environment:production`; apply; start a **new** staging run on the current `main` commit, then a **new** production run of the same commit (never "Re-run jobs" on an old run).
4. **Operate and recover**: roll back by reverting in Git and deploying again through staging and production; the health check needs `<<SITE_TITLE>>` in the page and in `main.tf` (change both together); caching is off and access logging is not enabled; after any rebuild update `WEBSITE_URL` and `SITE_BUCKET` and confirm the new SNS email; review costs and budget alerts.
5. **Teardown of one environment**: pause deployments first (Actions > Deploy website > "..." > Disable workflow); from `terraform/site`, `terraform init -reconfigure` with that environment's backend, and `terraform state list` shows the 15 resources; `terraform plan -destroy "-var-file=..\environments\staging\site.tfvars" "-out=staging-destroy.tfplan"`; review; `terraform apply staging-destroy.tfplan`, which ends with `Apply complete! Resources: 0 added, 0 changed, 15 destroyed.`; `terraform state list` then prints nothing (Terraform waits for AWS to confirm each deletion and keeps any failed one in the state); the state bucket, OIDC provider, budgets and SCP entries are separate decisions. Destroying the website bucket deletes every version of the page.
6. **Running the checks locally**: block G.

### 8.4 Blocks to copy word for word

<!-- BLOCK A START: Values you need -->
Replace every token below with your own real value. **Never commit these values**: they go only into the git-ignored `site.tfvars` and `backend.hcl`, command arguments, your local git settings and GitHub settings.

| Token | What it is | Where to find it | Where it goes |
|---|---|---|---|
| `<<AWS_ACCOUNT_ID>>` | The 12-digit AWS account that will host the site | AWS console, account menu at the top right; or `aws sts get-caller-identity` | `-ExpectedAccountId` of the bootstrap script |
| `<<GITHUB_OWNER>>` | The GitHub user or organization that owns the repository | The repository URL: `github.com/<owner>/<repository>` | Git remote URL, `site.tfvars` |
| `<<GITHUB_REPO>>` | The repository name | The repository URL | Git remote URL, `site.tfvars` |
| `<<GITHUB_OWNER_ID>>` | The owner's numeric ID | Public repository: open `https://api.github.com/repos/<<GITHUB_OWNER>>/<<GITHUB_REPO>>` and read `owner.id`. Private repository (that page returns 404 unless you are signed in): open the repository page while signed in, press Ctrl+U and search `octolytics-dimension-user_id` | `site.tfvars` |
| `<<GITHUB_REPO_ID>>` | The repository's numeric ID | The same API page, field `id`; or the page source, `octolytics-dimension-repository_id` | `site.tfvars` |
| `<<GITHUB_OIDC_PROVIDER_ARN>>` | The GitHub sign-in provider in your AWS account | IAM > Identity providers > `token.actions.githubusercontent.com`. It looks like `arn:aws:iam::<<AWS_ACCOUNT_ID>>:oidc-provider/token.actions.githubusercontent.com`. It is **not** the deploy role's ARN | `site.tfvars` |
| `<<ALERT_EMAIL>>` | The mailbox that receives health alerts | A real address you read; never `example.com` | `site.tfvars` |
| `<<SITE_BUCKET_NAME_STAGING>>` | A new, globally unique bucket name for the staging website | You choose it: 3 to 63 lowercase letters, digits and hyphens, for example `<<PROJECT_SLUG>>-staging-site-<yyyymmddhhmmss>` | Staging `site.tfvars` |
| `<<SITE_BUCKET_NAME_PRODUCTION>>` | The same for production | For example `<<PROJECT_SLUG>>-production-site-<yyyymmddhhmmss>` | Production `site.tfvars` |
| `<<GIT_AUTHOR_NAME>>`, `<<GIT_AUTHOR_EMAIL>>` | The name and verified email of the GitHub account that should own your commits | GitHub > Settings > Emails | `git config --local` before the first commit |
| `<<STATE_BUCKET_NAME>>` (optional) | An existing approved state bucket, only if you do not let the bootstrap script create one | Your AWS account | `backend.hcl` |

`github_repository` in `site.tfvars` must match the subject GitHub puts in its sign-in token. GitHub uses the ID form, so write it as `<<GITHUB_OWNER>>@<<GITHUB_OWNER_ID>>/<<GITHUB_REPO>>@<<GITHUB_REPO_ID>>`. If the first deploy still fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity", read the exact subject in CloudTrail (see Troubleshooting) and use the part between `repo:` and `:environment:`.

After `terraform apply`, set these **environment variables** (not repository variables) in GitHub > Settings > Environments > `staging` (and later `production`):

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `SITE_BUCKET` | `terraform output -raw site_bucket_name` |
| `WEBSITE_URL` | `terraform output -raw website_url` (no trailing slash) |
| `AWS_ROLE_ARN` | `terraform output -raw deploy_role_arn` |
<!-- BLOCK A END -->

<!-- BLOCK B START: One-time setup -->
Each step is needed once per account or repository. Check first; skip it if it is already done.

| Step | Where | Why you do it yourself | How to check it is already done |
|---|---|---|---|
| AWS account with a payment method, budget alerts and MFA on the root user | AWS console | Card details and account security are yours alone | Billing and Cost Management > Payment preferences shows a card; Budgets lists a budget |
| AWS CLI **version 2**, signed in to the account that will host the site | Your PC | Your keys or SSO sign-in are private. The scripts use `--no-cli-pager`, which version 1 rejects | `aws --version` shows `aws-cli/2.`; `aws sts get-caller-identity` shows `<<AWS_ACCOUNT_ID>>` |
| Your signed-in AWS identity may manage S3 buckets and policies, CloudFront distributions, origin access controls and response headers policies, IAM roles and inline policies, Route 53 health checks, SNS topics and subscriptions, and CloudWatch alarms; for teardown also list and delete S3 object versions | IAM or IAM Identity Center | This is your infrastructure identity, not the GitHub deploy role | `terraform plan` and `terraform apply` run without `AccessDenied` |
| Terraform 1.10 or later (below 2.0), Git, and Git Bash for `scripts/check-repo.sh` | Your PC | Installation | `terraform version`; `git --version`; `Test-Path "$env:ProgramFiles\Git\bin\bash.exe"` prints `True` |
| PowerShell may run local scripts | Your PC | Windows blocks scripts by default on many PCs | `Get-ExecutionPolicy` shows `RemoteSigned`, `Unrestricted` or `Bypass`. Otherwise run `Set-ExecutionPolicy -Scope Process Bypass` in that window only |
| GitHub sign-in provider for AWS (one per account, shared by projects) | IAM > Identity providers > Add provider > OpenID Connect. Provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com` | Account-wide setting | `token.actions.githubusercontent.com` is listed with audience `sts.amazonaws.com` |
| CloudFront account verification, **only if** apply fails with "Your account must be verified before you can add new CloudFront resources" | Support Center > Create case > Account and billing > Account Activation > Account Verification | Only AWS Support can lift it | The case shows Resolved |
| Organization region policy, **only if** a command fails with "explicit deny in a service control policy" | See "If AWS says explicit deny in a service control policy" below | Only the management account can change it | The policy's exceptions include every action in the list below |
| An empty GitHub repository (no README, license or .gitignore) with default branch `main` | github.com > New repository | Ownership and visibility are your choice | The repository page loads; Settings > General shows default branch `main` |
| A GitHub plan that supports environments for this repository | Repository visibility or your GitHub plan | Environments exist on every plan for **public** repositories. **Private** repositories need GitHub Pro or Team (or Enterprise) for environments, and Enterprise for required reviewers. The deploy role trusts only environment tokens, so without environments nothing can deploy | Settings shows an "Environments" entry |
| Protect `main`: pull request review and the required checks `validate` and `scripts` (recommended) | Settings > Rules > Rulesets (or Settings > Branches) | Repository policy | The rule lists `main` and both checks |
| Environment `staging`, and later `production` | Settings > Environments > New environment; Deployment branches and tags > Selected branches and tags > add `main` | Repository settings | The environment exists with the `main` rule; production also has required reviewers where your plan allows. **Create `production` before any production run**: starting a run for a missing environment makes GitHub create it with no protection and no variables |
| The four environment variables (Values you need) | Settings > Environments > `<env>` > Environment variables | They come from your Terraform outputs | All four are present on the environment |
| Confirm the alert email | The `<<ALERT_EMAIL>>` inbox: "AWS Notification - Subscription Confirmation" > Confirm subscription | Only the mailbox owner can confirm; the link expires after 3 days | SNS (region us-east-1) > Topics > `<<PROJECT_SLUG>>-<env>-alerts` > Subscriptions shows Confirmed |
| Run the deploy | Actions > Deploy website > Run workflow > branch `main` > environment | Releases are deliberate | A green run |
<!-- BLOCK B END -->

<!-- BLOCK C START: Service control policy -->
#### If AWS says "explicit deny in a service control policy"

Your AWS Organization has a policy that blocks actions in some regions unless they are listed as exceptions. IAM permissions in your own account cannot override it. Only someone who can sign in to the **management account** can change it.

1. Sign in to the management account. Open **AWS Organizations > Policies > Service control policies** and open the region policy attached to your account or its organizational unit.
2. Copy the whole policy JSON into a file on your PC before you change anything. SCPs keep no history.
3. Choose **Edit policy**. In the statement that denies actions by region (it has `"Effect": "Deny"` and a `NotAction` list), make sure `NotAction` contains every action below. Add the missing ones and keep everything else. Your administrators may prefer to limit these exceptions to your account.

   ```text
   s3:*
   sns:*
   cloudwatch:PutMetricAlarm
   cloudwatch:DeleteAlarms
   cloudwatch:TagResource
   cloudwatch:UntagResource
   cloudwatch:Describe*
   cloudwatch:Get*
   cloudwatch:List*
   cloudfront:*
   iam:*
   route53:*
   sts:*
   cloudtrail:LookupEvents
   ```

4. Save. The change applies at once to every account under the policy. Run the failed command again. If the bootstrap script failed after creating a bucket, inspect that bucket before you retry.
<!-- BLOCK C END -->

<!-- BLOCK D START: Expected output -->
Your bucket names, IDs and paths will differ.

**Bootstrap preview (`-WhatIf`), first time:**

```text
[OK]      AWS CLI account matches ExpectedAccountId
What if: Performing the operation "Create state bucket <<PROJECT_SLUG>>-v1-staging-state-<32 hex characters> for staging" on target "AWS account <<AWS_ACCOUNT_ID>>, region us-east-1".
```

**Bootstrap real run** (it first asks `Are you sure you want to perform this action?`; answer `Y`):

```text
[OK]      AWS CLI account matches ExpectedAccountId
Applied: public access block
Applied: versioning
Applied: default encryption (AES256)
Applied: HTTPS-only bucket policy
Created and verified state bucket: <<PROJECT_SLUG>>-v1-staging-state-<32 hex characters>
Created backend configuration: <repository>\terraform\environments\staging\backend.hcl
The bucket is separate from the website and must be reviewed separately during teardown.
```

**Bootstrap run again** (safe at any time; it only checks):

```text
[OK]      AWS CLI account matches ExpectedAccountId
Found <repository>\terraform\environments\staging\backend.hcl; checking the bucket it names. No new bucket will be created.
[OK]      Bucket <<PROJECT_SLUG>>-v1-staging-state-<32 hex characters> exists and belongs to account <<AWS_ACCOUNT_ID>>
[OK]      Bucket region is us-east-1
[INFO]    No Terraform state file at <<PROJECT_TAG>>/staging/terraform.tfstate yet (normal before the first apply)
[OK]      Public access block (all four settings on): already applied
[OK]      Versioning enabled: already applied
[OK]      Default encryption (AES256): already applied
[OK]      HTTPS-only bucket policy: already applied
Everything is already applied. Nothing was changed; backend.hcl was left as it is.
```

**`terraform plan`** for a new environment ends with:

```text
Plan: 15 to add, 0 to change, 0 to destroy.
```

**`terraform apply staging.tfplan`** takes several minutes (CloudFront is the slowest) and ends with:

```text
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.

Outputs:

aws_account_id = "<<AWS_ACCOUNT_ID>>"
deploy_role_arn = "arn:aws:iam::<<AWS_ACCOUNT_ID>>:role/<<PROJECT_SLUG>>-staging-github-deploy"
site_bucket_name = "<<SITE_BUCKET_NAME_STAGING>>"
website_url = "https://<random>.cloudfront.net"
```

**Deploy website** run, last step:

```text
Verified release <commit SHA> at https://<random>.cloudfront.net
```

**Teardown**: `terraform apply staging-destroy.tfplan` ends with `Apply complete! Resources: 0 added, 0 changed, 15 destroyed.`, and `terraform state list` then prints nothing.

**`scripts/check-repo.sh`** (run with Git Bash, see "Running the checks locally" in `docs/operations.md`) prints six `[OK]` lines and `All repository checks passed.`
<!-- BLOCK D END -->

<!-- BLOCK E START: Troubleshooting -->
| # | What you see | Why | What to do |
|---|---|---|---|
| 1 | Apply fails: "Your account must be verified before you can add new CloudFront resources" | New AWS accounts are held back from CloudFront | Open the Support case in One-time setup; plan and apply again when it is Resolved |
| 2 | The bootstrap's `s3:CreateBucket` or apply's `sns:CreateTopic` fails "... with an explicit deny in a service control policy" | The organization's region policy blocks it | Follow "If AWS says explicit deny in a service control policy"; IAM permissions cannot override it |
| 3 | Deploy step "Configure AWS credentials with OIDC" retries, then "Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity" | `github_oidc_provider_arn` still holds the example account `123456789012`, or `github_repository` is the plain `owner/repo` form while GitHub sends `owner@ownerId/repo@repoId` | Fix `site.tfvars`, plan and apply (only the deploy role's trust changes), then start a **new** run. To read the exact subject: CloudTrail (region us-east-1) > Event history > Event name = `AssumeRoleWithWebIdentity` > open the failed event > `userIdentity.userName` |
| 4 | Apply fails: "MalformedPolicyDocument: Federated principals must be valid domain names or SAML metadata ARNs" | The deploy **role** ARN was put in `github_oidc_provider_arn` | Use the `oidc-provider/token.actions.githubusercontent.com` ARN |
| 5 | The SNS subscription stays "PendingConfirmation"; no alert emails | `alert_email` is still the example, or the email was never confirmed | Use a real mailbox, apply, and click "Confirm subscription" within 3 days, or SNS > Subscriptions > Request confirmation |
| 6 | The site returns 403 right after apply and the alarm is in ALARM | Normal: the bucket is empty until the first deploy | Run Deploy website |
| 7 | The upload works but "Verify the public page matches this release" fails after about 2 minutes | `WEBSITE_URL` still points at an old CloudFront address; every destroy and new apply creates a new one | Update `WEBSITE_URL` (and `SITE_BUCKET` if it changed) and confirm the new SNS email |
| 8 | Creating the website bucket fails right after a destroy | The old bucket name is still being released | Wait a few minutes and plan again, or choose a new name and update `SITE_BUCKET` |
| 9 | "Saved plan is stale", or apply refuses a plan | A saved plan can be applied only once | Run `terraform plan ... -out=...` again |
| 10 | Production fails: "No successful staging deployment found for <SHA>." | Production needs the same commit to have succeeded in staging; "Re-run jobs" reuses an old commit | Start a new staging run on the current `main` commit, then a new production run |
| 11 | A script stops at the first AWS warning or error line after you edited it | Windows PowerShell 5.1 turns `2>&1` output into a terminating error under `$ErrorActionPreference = "Stop"` | Keep the `Invoke-AwsRaw` pattern: local `Continue`, then check `$LASTEXITCODE` |
| 12 | `git commit -m "... \"quoted\" ..."` in PowerShell turns words into file paths | PowerShell 5.1 splits native arguments at inner double quotes | Write the message to a file and use `git commit -F <file>` |
| 13 | GitHub shows an unexpected contributor | The commit email belongs to another GitHub account, for example a global work identity | Set `git config --local user.name` and `user.email` before the first commit; rewriting pushed history needs a force-push, so decide that carefully |
| 14 | `Checks` fails at `terraform init -lockfile=readonly` | The lock file is missing or selects a different provider version | Commit `terraform/site/.terraform.lock.hcl` unchanged |
| 15 | The health check fails although the page loads | The page title and `search_string` in `main.tf` differ, or the title moved beyond the first 5,120 bytes | Keep them identical and near the top; `scripts/check-repo.sh` checks this |
| 16 | JavaScript, images or fonts do not load | The Content Security Policy allows only inline styles | Widen the policy in `main.tf` deliberately, for example `script-src 'self'` |
| 17 | Visitors see an old page | Only possible if caching is turned on (it is off by design) | Keep caching off, or add a CloudFront invalidation step and `cloudfront:CreateInvalidation` for the deploy role |
| 18 | The bootstrap creates a second state bucket | `backend.hcl` was deleted, so the script assumed a first-time setup | Never delete `backend.hcl` while the environment exists; it is git-ignored on purpose |
| 19 | The bootstrap's real run fails with "Windows PowerShell is in NonInteractive mode. Read and Prompt functionality is not available." | It asks for confirmation, and the shell cannot answer (for example an agent or a scheduled task) | Run it yourself in a PowerShell window and answer `Y`, or add `-Confirm:$false` there |
| 20 | Adding `-Confirm:$false` fails with "Cannot convert 'System.String' to the type 'System.Management.Automation.SwitchParameter' required by parameter 'Confirm'." | The script was started with `powershell -File`, which passes `$false` as text | Type the command in a PowerShell window instead |
| 21 | `Checks` never runs on push, and Deploy website is skipped | The branch is not called `main` | `git branch -M main`, push `main`, and make it the default branch |
| 22 | GitHub has no Environments settings, or deploys from a private repository cannot assume the role | Your GitHub plan has no environments for private repositories | Make the repository public, or use a plan that supports them |
| 23 | A production run has no reviewers, or fails because its variables are empty | `production` was started before the environment existed, so GitHub created it bare | Create `production` with its branch rule, reviewers and four variables before any production run |
| 24 | `curl -I <url>` in Windows PowerShell errors or prints an object | `curl` is an alias of `Invoke-WebRequest` there | Use `curl.exe` |
| 25 | A script that worked fails to parse after an edit | A smart quote or long dash was saved in a UTF-8 file without a byte order mark | Keep `.ps1` files plain ASCII; `scripts/check-repo.sh` and the `scripts` check catch this |
| 26 | `Checks` fails at "Check repository rules" | A `[FAIL]` line names the problem: page title and health check differ, an unfilled token, an account ID or GitHub ID pair in a file, a non-ASCII character in a script, or a local-only file not ignored | Fix what the `[FAIL]` line names, then push again |
| 27 | `bash scripts/check-repo.sh` typed in PowerShell starts WSL, fails with Linux errors, or says `bash` is not recognized | In PowerShell, `bash` is usually WSL's `C:\Windows\System32\bash.exe` or nothing at all: Git Bash's `bash.exe` is in `C:\Program Files\Git\bin`, which is usually not on PATH | Run it in Git Bash, or in PowerShell with `& "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh` |
| 28 | The `.terraform` folder in `terraform\site` is about 630 MB | `terraform init` unpacks the AWS provider there | It is git-ignored and safe to delete; the next `terraform init` downloads it again |
| 29 | `check-repo.sh` stops after a `grep:` or `fatal:` line, without "All repository checks passed." or "Repository checks failed." | A search could not run, for example "grep: scripts/*.ps1: No such file or directory" when the `scripts` folder holds no `.ps1` files. The script stops rather than report a check it could not run as passed | Fix what the error line names, then run it again |
<!-- BLOCK E END -->

<!-- BLOCK F START: Check the deployment -->
After the deploy is green and you have confirmed the email, run these from `terraform\site` in Windows PowerShell. They only read.

```powershell
$url = terraform output -raw website_url
$bucket = terraform output -raw site_bucket_name
$domain = $url -replace '^https://', ''

# 200 with the security headers
curl.exe -sS -I "$url/"

# HTTP redirects to HTTPS: prints 301 https://<domain>/
curl.exe -sS -o NUL -w '%{http_code} %{redirect_url}' "http://$domain/"

# The bucket itself is private: prints 403
curl.exe -sS -o NUL -w '%{http_code}' "https://$bucket.s3.us-east-1.amazonaws.com/index.html"

# The alarm reads "OK" (allow up to about 5 minutes after the first deploy)
aws cloudwatch describe-alarms --region us-east-1 --alarm-names <<PROJECT_SLUG>>-staging-unavailable --query "MetricAlarms[0].StateValue"

# The email subscription prints an ARN, not "PendingConfirmation"
aws sns list-subscriptions-by-topic --region us-east-1 --topic-arn "arn:aws:sns:us-east-1:<<AWS_ACCOUNT_ID>>:<<PROJECT_SLUG>>-staging-alerts" --query "Subscriptions[0].SubscriptionArn"

# The page's commit matches the deployed commit
aws s3api head-object --bucket $bucket --key index.html --query "Metadata.commit"
```

In the `curl.exe -I` output, look for `content-security-policy`, `strict-transport-security: max-age=31536000`, `x-content-type-options: nosniff`, `x-frame-options: DENY`, `referrer-policy: no-referrer`, `cache-control: no-cache` and `x-cache: Miss from cloudfront`. The Deploy website run has already compared the live page with `web/index.html` byte for byte.
<!-- BLOCK F END -->

<!-- BLOCK G START: Running the checks locally -->
These are the checks the `Checks` workflow runs on GitHub. They only read files; nothing changes in AWS or GitHub.

**Repository rules (Git Bash).** Open **Git Bash** (Start menu > Git Bash), go to the repository folder and run:

```bash
bash scripts/check-repo.sh
```

It prints six `[OK]` lines and `All repository checks passed.` Do not type `bash` in PowerShell: there it usually starts WSL or is not found. From PowerShell, call Git Bash directly:

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh
```

**Terraform (PowerShell, from the repository root).** The first `init` puts the AWS provider in `terraform\site\.terraform`, about 630 MB on disk. That folder is git-ignored and safe to delete afterwards. The warning "Provider lock file not updated" is harmless.

```powershell
terraform fmt -check -recursive terraform
Set-Location .\terraform\site
terraform init -backend=false -lockfile=readonly
terraform validate
Set-Location ..\..
```

`terraform fmt` prints nothing when the formatting is correct, and `terraform validate` prints `Success! The configuration is valid.`

**Script syntax (Windows PowerShell 5.1, from the repository root).** This is the parser from the `scripts` check, but it prints a message instead of exiting, so the window stays open:

```powershell
$failed = $false
foreach ($file in Get-ChildItem -Path scripts -Filter *.ps1) {
  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
  foreach ($parseError in $parseErrors) {
    Write-Host "$($file.Name):$($parseError.Extent.StartLineNumber): $($parseError.Message)"
    $failed = $true
  }
}
if ($failed) { Write-Host "Parse errors found. Fix the lines above." } else { Write-Host "All scripts parse in Windows PowerShell $($PSVersionTable.PSVersion)." }
```
<!-- BLOCK G END -->

## 9. Why the reference looks the way it does

These problems happened on the reference project or are known risks; the code and blocks above already handle them. Do not undo any of these choices.

- The bootstrap checks rather than creates when `backend.hcl` exists, verifies every setting after writing it, and refuses to overwrite `backend.hcl`: a second state bucket would make Terraform lose track of the environment.
- The bootstrap script calls native commands with a local `$ErrorActionPreference = "Continue"`, reads `$LASTEXITCODE`, and keeps stderr out of parsed JSON: Windows PowerShell 5.1 otherwise stops at the first warning.
- `github_repository` accepts the ID form because GitHub put numeric IDs in the token subject for the reference repository.
- Caching is off so a new upload is visible at once without an invalidation permission.
- `check-repo.sh` guards the mistakes that broke or leaked things before: a title that no longer matches the health check, leftover tokens, committed account or repository IDs, non-ASCII scripts and unignored local files. It treats only "no match" (exit code 1) from `git grep` and `grep` as a pass and stops on any other error, so a search that could not run is never reported as `[OK]`.
- The local docs never put `bash` in a PowerShell command: on Windows, `bash` in PowerShell is usually WSL, not Git Bash.

## 10. Verify locally (no AWS, no GitHub)

Run these and keep each result for the report:

1. Run `scripts/check-repo.sh` with Git Bash: `bash scripts/check-repo.sh` in a Git Bash shell, or `& "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh` from PowerShell (never plain `bash` in PowerShell, which is usually WSL). It prints six `[OK]` lines and `All repository checks passed.`
2. `terraform fmt -check -recursive terraform` prints nothing and exits 0.
3. In `terraform/site`: `terraform init -backend=false -lockfile=readonly` (it puts the AWS provider in the git-ignored `terraform/site/.terraform` folder, about 630 MB on disk; leave it there; the warning "Provider lock file not updated" is harmless), then `terraform validate`, which prints `Success! The configuration is valid.` Afterwards `.terraform.lock.hcl` must be unchanged.
4. In Windows PowerShell 5.1 (`powershell.exe`), from the repository root, run the script-syntax block from block G (the `scripts` job in `checks.yml` runs the same parser); it prints `All scripts parse in Windows PowerShell 5.1...`. Without `powershell.exe`, run it with `pwsh` and report "parsed with PowerShell 7 only", or mark it NOT RUN.
5. Both workflow files are valid YAML, for example `python -c "import sys, yaml; [yaml.safe_load(open(f, encoding='utf-8')) for f in sys.argv[1:]]" .github/workflows/checks.yml .github/workflows/deploy.yml`. Without Python and PyYAML, mark it NOT RUN.
6. **Fidelity:** compare every file you created from section 7 with its reference after replacing the five tokens. Any other difference is a failure: fix it. A difference you made on purpose is still a failure: restore the reference and describe your idea under "Suggested fixes".
7. **Docs:** blocks A to G appear word for word; no section 4.1 token is left anywhere (`git grep --untracked -n -E "<<(PROJECT_SLUG|PROJECT_TAG|SITE_TITLE|SITE_EYEBROW|SITE_TAGLINE)>>"` prints nothing); every section 4.2 token used in the docs is in block A.
8. `git status --short` lists only the files of section 6 as untracked (`??`), nothing is staged, and `git branch --show-current` prints `main`.

## 11. Final report

End your run with this report, and nothing after it:

1. **Decisions**: the five values you chose and why, and any other choice you made.
2. **Files created**: the list.
3. **Checks**: for each check in section 10, the command, PASS, FAIL or NOT RUN, and the key output line.
4. **Suggested fixes**: anything in the reference you believe is wrong, with the reason (or "none").
5. **Before you deploy**: every section 4.2 token the operator must replace, pointing to the "Values you need" table, and these next steps: review the files; `git config --local user.name` and `user.email`; stage by path and commit; create the GitHub repository; add the remote and push; follow `docs/staging-deployment.md`.

<!-- PROMPT END -->
