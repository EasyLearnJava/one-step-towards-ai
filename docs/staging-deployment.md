# Staging deployment: step by step

These instructions use Windows PowerShell, an S3 state bucket and website
bucket in N. Virginia (`us-east-1`), and the GitHub repository
`EasyLearnJava/one-step-towards-ai`. Commands start at the repository root
unless stated otherwise. Review costs and permissions before creating AWS
resources; a failed deployment can still leave billable resources behind.

## 1. Prepare AWS

1. Install the AWS CLI and Terraform 1.10 or later. Sign in with an approved
   infrastructure identity and run:

   ```powershell
   # Show the AWS account and identity used by the current credentials.
   aws sts get-caller-identity
   ```

   Check the account before continuing; do not share credentials.
2. Resolve any CloudFront account-verification requirement with AWS Support.
   The organization must also permit the necessary monitoring operations in
   `us-east-1`: Route 53 health-check metrics and this project's SNS topic and
   CloudWatch alarm use that region.
3. In IAM, open **Identity providers**. Reuse the provider for
   `https://token.actions.githubusercontent.com` if present; its audience
   must include `sts.amazonaws.com`. Otherwise, create an **OpenID Connect**
   provider using that URL and audience. Copy its ARN. An account can have
   only one provider for this URL; it may be shared with other projects.

## 2. Prepare the Terraform state bucket

Reuse an approved private state bucket if one already exists. Otherwise,
create a general-purpose S3 bucket in `us-east-1` with a globally unique name,
all public access blocked, versioning enabled, and SSE-S3 encryption. Use a
different bucket from the website bucket. Restrict state and lock-file access
to the approved infrastructure identity; public access blocking alone does
not restrict other IAM principals.

For clarity, use names such as `one-step-towards-ai-staging-state-<unique-suffix>`
for the state bucket and `one-step-towards-ai-staging-site-<unique-suffix>`
for the website bucket. Bucket names must be globally unique, so check that
your chosen names are available.

### If bucket creation is denied by a service control policy

An error saying that `s3:CreateBucket` has an **explicit deny in a service
control policy (SCP)** means an AWS Organizations policy is blocking the
request. Adding permissions to the IAM role alone cannot override that deny.
The same restriction can also prevent Terraform from creating the website
bucket.

1. Confirm the AWS account and requested bucket region, and give the
   organization administrator the error, including the SCP ID. Do not share
   credentials.
2. Ask the administrator to inspect that policy and its attachments in the
   AWS Organizations management account. The deny may be intentional or
   conditional, for example on the requested region.
3. If permitted by the organization, the administrator should review a
   narrowly scoped policy change for the necessary account, region, and
   actions. Do not remove a broad deny without understanding its effect on
   other accounts and resources. The deployment identity still needs the
   appropriate IAM permissions.
4. After the approved change, retry bucket creation. Alternatively, use an
   approved existing state bucket, with its actual region in `backend.hcl`;
   the website bucket and monitoring operations must still be permitted.
   If a previous attempt may have created a bucket, inspect it before
   retrying rather than creating duplicate resources.

To require HTTPS for the state bucket:

1. In the AWS Console, open **S3 > Buckets** and select the state bucket.
2. Select **Permissions**, find **Bucket policy**, and select **Edit**.
3. Paste the policy below, replacing both occurrences of
   `YOUR-STATE-BUCKET-NAME` with the actual state bucket name.
4. Select **Save changes**. Keep **Block all public access** enabled.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::YOUR-STATE-BUCKET-NAME",
        "arn:aws:s3:::YOUR-STATE-BUCKET-NAME/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
```

Create `terraform\environments\staging\backend.hcl` from
`backend.example.hcl` if it does not already exist. First check manually
whether `backend.hcl` exists; if it does, inspect it instead of running the
copy command, which would overwrite it. If it is absent, run this from the
repository root:

```powershell
# Copy the template to create the local backend configuration.
Copy-Item .\terraform\environments\staging\backend.example.hcl .\terraform\environments\staging\backend.hcl
```

Then update the file with your state bucket name:

```hcl
bucket = "YOUR-STATE-BUCKET-NAME"
key    = "one-step-at-a-time/staging/terraform.tfstate"
region = "us-east-1"
```

Update `terraform\environments\staging\backend.hcl`: replace the `bucket`
placeholder with your state bucket name, and check that `key` and `region`
match your intended state location. The bootstrap script refuses to overwrite
an existing `backend.hcl`.

`backend.example.hcl` is a reusable template. `backend.hcl` contains the
actual state location for your environment and is ignored by Git, so it
does not normally appear in a new checkout.

The region must match the actual state bucket. Changing this setting does not
move an existing bucket or its state. If moving existing state to a different
bucket, follow an approved state migration procedure instead of merely
reconfiguring the backend. State is sensitive; do not share it or commit the
backend file. The state bucket and OIDC provider are not created or destroyed
by the site Terraform configuration.

## 3. Configure and provision the site

`site.example.tfvars` is a reusable template with placeholders. The local
`site.tfvars` contains your environment-specific settings and is ignored by
Git, keeping those values out of the repository. Do not put credentials in
either file.

Create `site.tfvars` from the example if it does not already exist. First
check manually whether `site.tfvars` exists; if it does, inspect it instead of
running the copy command, which would overwrite it. If it is absent, run
this from the repository root:

```powershell
# Copy the template to create the local site configuration.
Copy-Item .\terraform\environments\staging\site.example.tfvars .\terraform\environments\staging\site.tfvars
```

Edit `site.tfvars` and set `aws_region = "us-east-1"`,
`environment = "staging"`, a globally unique website bucket name, the
repository above, the OIDC provider ARN, and an alert email address. S3 bucket
names cannot contain underscores.

The `site_bucket_name` is for the website bucket that Terraform creates during
apply. It must be different from the state bucket created earlier. The
following optional command suggests a unique website bucket name; you can
choose another available name instead:

```powershell
# Print a candidate name; this does not create a bucket.
"one-step-towards-ai-staging-site-$(Get-Date -Format 'yyyyMMddHHmmss')"
```

The timestamp does not guarantee uniqueness; S3 checks the name's availability
when the bucket is created. Do not put credentials in the file.

```powershell
# Change to the directory containing the site Terraform configuration.
Set-Location .\terraform\site

# Initialize Terraform and configure the state backend; this does not migrate state.
terraform init -reconfigure "-backend-config=..\environments\staging\backend.hcl"

# Preview changes using the staging settings and save the plan; this does not apply it.
terraform plan "-var-file=..\environments\staging\site.tfvars" "-out=staging.tfplan"

# Display the saved plan for review.
terraform show staging.tfplan
```

Review the account, resources, permissions, and charges. Only if the plan is
correct, run:

```powershell
# Apply the reviewed plan to create or change AWS resources.
terraform apply staging.tfplan

# Show values needed for GitHub deployment and the website URL.
terraform output
```

Saved plans may contain sensitive data. If apply fails, inspect the error and
Terraform state; resources may already exist. After fixing the cause, create
and review a fresh plan rather than reusing the failed plan. Confirm the SNS
subscription email to receive alerts.

## 4. Publish using GitHub Actions

Push the project to the intended repository. Create a GitHub environment named
`staging`, restrict it to `main`, and set these environment variables:

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `SITE_BUCKET` | Terraform output `site_bucket_name` |
| `WEBSITE_URL` | Terraform output `website_url`, without a trailing slash |
| `AWS_ROLE_ARN` | Terraform output `deploy_role_arn` |

In **Actions > Deploy website**, select `main` and `staging`, then run the
workflow. It uploads `web/index.html` and verifies the public response. Open
the CloudFront URL and check the health alarm and confirmed email subscription.
Deployments are manual, not automatic on push.

## 5. Clean up safely

Before deleting anything, identify the account and environment, pause
deployments, and save any needed data. Destroying the website bucket deletes
all its object versions. Never delete the state bucket before Terraform
cleanup is complete and verified.

From `terraform\site`, inspect the current state and review a destroy plan:

```powershell
# Check which AWS account and identity will be used.
aws sts get-caller-identity

# List resources and data sources recorded in the current Terraform state.
terraform state list

# Preview and save the staging deletion plan; this does not delete resources.
terraform plan -destroy "-var-file=..\environments\staging\site.tfvars" "-out=staging-destroy.tfplan"

# Display the saved deletion plan for review.
terraform show staging-destroy.tfplan
```

Only if the plan contains the intended resources, run:

```powershell
# Permanently delete the resources listed in the reviewed destroy plan.
terraform apply "staging-destroy.tfplan"
```

Verify the resulting state and AWS resources; a failed apply can leave
resources not represented in state. Follow
the [full teardown checklist](operations.md#7-teardown-and-verify-one-environment).
Its inventory checker expects a complete deployment, so it may not work after
a partial apply; inspect the state and AWS resources directly in that case.

Keep the state bucket and OIDC provider if their ownership or other uses are
uncertain. Remove local `backend.hcl`, `site.tfvars`, and saved plan files only
after cleanup and verification; retain the example files for the next run.
