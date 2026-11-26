# Copy to site.tfvars and replace every value below.
# github_repository must match GitHub's OIDC subject exactly. This
#   repository's tokens use the ID form:
#   <owner>@<owner-id>/<repo>@<repo-id>
# github_oidc_provider_arn is the oidc-provider ARN in the production account
#   (IAM > Identity providers), not the deploy role ARN.
# alert_email must be a real mailbox; confirm the SNS subscription from it.

aws_region               = "us-east-1"
environment              = "production"
site_bucket_name         = "replace-with-globally-unique-production-bucket"
github_repository        = "replace-owner/replace-repository"
github_oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
alert_email              = "replace@example.com"
