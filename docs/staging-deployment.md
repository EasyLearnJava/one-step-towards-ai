# Staging deployment: step by step

These instructions use Windows PowerShell, an S3 state bucket and website
bucket in N. Virginia (`us-east-1`), and the GitHub repository
`<owner>/<repo>`. Commands start at the repository root
unless stated otherwise. Review costs and permissions before creating AWS
resources; a failed deployment can still leave billable resources behind.

## Before you start: which AWS account does what

This setup uses an AWS Organization with separate accounts. On the
**AWS sign-ins** page each account is a card: select **Sign in** on a card, or
its name if it is already signed in. Signing in only opens a console session;
it changes nothing.

| Account | Used for |
|---|---|
| Workload account | Everything this guide creates: state bucket, OIDC provider, website bucket, CloudFront, deploy role, health check, alarm and SNS topic. The AWS CLI and Terraform must use this account. |
| Management account | The organization's service control policies (section 1, step 3) and the combined bill and credits (section 5). |
| Identity Center delegated admin account, if present | Manages users and sign-in permissions. Nothing to do for this project. |

## 1. Prepare AWS

1. **Tools and identity.** Install the AWS CLI and Terraform 1.10 or later
   (`versions.tf` requires `>= 1.10.0, < 2.0.0`). Configure the CLI with an
   approved infrastructure identity for the workload account, then run:

   ```powershell
   # Show the AWS account and identity used by the current credentials.
   aws sts get-caller-identity
   ```

   Check that `Account` is the workload account; do not share credentials.

2. **CloudFront account verification.** A new account can fail with "Your
   account must be verified before you can add new CloudFront resources".
   The hold covers the whole account, not one region. Signed in to the
   workload account:

   1. Open **Support Center**: type `Support` in the console search bar, or
      go to `https://console.aws.amazon.com/support/home`.
   2. Describe the problem in the text box and paste the error text. AWS
      first shows an automated answer; select **Create a case**.
   3. Choose **Case type: Account and billing**, **Service: Account
      Activation**, **Category: Account Verification** and **Severity:
      General question**. Account and billing cases are free on the Basic
      support plan.
   4. Use a subject such as "Account verification needed to create
      CloudFront distributions", keep the error text in the description, and
      submit.
   5. Wait until AWS resolves the case, shown in Support Center's case list,
      before running `terraform apply`.

3. **Region service control policy (SCP).** Route 53 health-check metrics
   exist only in `us-east-1`, so the CloudWatch alarm and SNS topic must be
   there too, and this guide also puts both buckets there. If the
   organization restricts regions, `terraform apply` or bucket creation fails
   with "explicit deny in a service control policy" and the policy's ID
   (`p-...`). Adding IAM permissions cannot override that deny. Signed in to
   the **management account**:

   1. Open **AWS Organizations > Policies > Service control policies** and
      open the policy whose ID is in the error. In this organization it is
      `AdvancedModeRegionRestrictionSecurityControlPolicy`. Its **Targets**
      tab shows **Root**, so it applies to every account.
   2. On the **Content** tab, find the statement with
      `"Sid": "UsEast1Partitional"`. It is a `Deny` with a `NotAction` list
      and the condition `aws:RequestedRegion` = `us-east-1`. Every action in
      that list is exempt, so allowed in `us-east-1`; everything else is
      denied there.
   3. Copy the whole policy JSON into a local file as a backup. SCPs keep no
      version history, so that copy is the only way back.
   4. Select **Edit policy**. In the `UsEast1Partitional` `NotAction` list
      only:
      - replace all the separate `"s3:..."` entries with one `"s3:*"` (state
        bucket, website bucket and the deploy upload);
      - add `"sns:*"` (alert topic and email subscription);
      - add `"cloudwatch:PutMetricAlarm"`, `"cloudwatch:DeleteAlarms"`,
        `"cloudwatch:TagResource"` and `"cloudwatch:UntagResource"` (create,
        tag and delete the health alarm).

      Each entry is in double quotes and followed by a comma, except the last
      entry in the list. Leave the other statements unchanged.
   5. Select **Save changes**. The editor may mark a few entries that were
      already in the policy as errors; they do not block saving. Reload the
      page and check that the new entries are there. The change takes effect
      at once for every account under the target.

   The same list must also still contain `cloudfront:*`, `iam:*`,
   `route53:*`, `sts:*` (GitHub's sign-in to AWS), `cloudwatch:Describe*`,
   `cloudwatch:Get*`, `cloudwatch:List*` and `cloudtrail:LookupEvents`; in
   this organization they were already there. If the policy is ever changed
   or regenerated and errors for S3, SNS or CloudWatch in `us-east-1` return,
   check this list first.

4. **GitHub OIDC provider.** Signed in to the workload account:

   1. Open **IAM**, then **Identity providers** under **Access management**
      in the left menu.
   2. If `token.actions.githubusercontent.com` is listed, open it and check
      that its audiences include `sts.amazonaws.com`. Reuse it: an account
      can have only one provider for this URL, and other projects may use it.
   3. Otherwise select **Add provider**, choose **OpenID Connect**, enter the
      provider URL `https://token.actions.githubusercontent.com` and the
      audience `sts.amazonaws.com`, and select **Add provider**.
   4. Copy the provider's ARN. It has the form
      `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`.
      It is not the deploy role ARN that Terraform outputs later.

## 2. Prepare the Terraform state bucket

Reuse an approved private state bucket if one already exists. Otherwise create
one in the workload account, separate from the website bucket. Bucket names
are global, so pick a unique one such as
`one-step-towards-ai-staging-state-<unique-suffix>`.

**Option A, AWS console:**

1. Set the console region at the top right to **United States
   (N. Virginia) us-east-1**, then open **S3 > Buckets > Create bucket**.
2. Choose **General purpose** and enter the bucket name.
3. Keep **ACLs disabled**, keep **Block all public access** selected, set
   **Bucket Versioning** to **Enable**, and keep default encryption as
   **SSE-S3**.
4. Select **Create bucket**, then add the HTTPS-only policy below.

To require HTTPS for the state bucket:

1. Open **S3 > Buckets** and select the state bucket.
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

**Option B, script:** `scripts\bootstrap-state.ps1` creates a bucket named
`one-step-v1-staging-state-<random>` with the same settings and HTTPS-only
policy, checks them, and writes `backend.hcl` for you. Preview first, then run
without `-WhatIf`:

```powershell
# Preview; replace the account ID with the workload account's 12-digit ID.
.\scripts\bootstrap-state.ps1 -Environment staging -Region us-east-1 -ExpectedAccountId "123456789012" -WhatIf
```

If `backend.hcl` already exists, the script creates nothing new. It checks
the bucket named there and prints each setting as `[OK]` (already applied) or
`[MISSING]`; it applies only the missing ones after you confirm, and changes
nothing when everything is already applied. It never creates a second bucket
or rewrites `backend.hcl`, so it is also a safe way to check an existing
state bucket.

### If bucket creation is denied by a service control policy

An error saying that `s3:CreateBucket` has an **explicit deny in a service
control policy (SCP)** is the organization policy from section 1, step 3.
Follow those steps in the management account, then retry. If a previous
attempt may have created a bucket, inspect it before retrying rather than
creating a duplicate.

### Point Terraform at the state bucket

With Option A, create `terraform\environments\staging\backend.hcl` from the
template. First check whether `backend.hcl` already exists; if it does,
inspect it instead, because the copy command would overwrite it:

```powershell
# Copy the template to create the local backend configuration.
Copy-Item .\terraform\environments\staging\backend.example.hcl .\terraform\environments\staging\backend.hcl
```

Then set your state bucket name:

```hcl
bucket = "YOUR-STATE-BUCKET-NAME"
key    = "one-step-at-a-time/staging/terraform.tfstate"
region = "us-east-1"
```

`backend.hcl` holds the actual state location and is ignored by Git, so it
does not appear in a new checkout. The region must match the bucket's actual
region; changing it does not move a bucket or its state. State is sensitive;
do not share it or commit the backend file. The state bucket and OIDC
provider are not created or destroyed by the site Terraform configuration.

## 3. Configure and provision the site

`site.example.tfvars` is a template with placeholders. The local
`site.tfvars` holds your settings and is ignored by Git. Do not put
credentials in either file.

Create `site.tfvars` from the example if it does not already exist. First
check whether it exists; if it does, inspect it instead, because the copy
command would overwrite it:

```powershell
# Copy the template to create the local site configuration.
Copy-Item .\terraform\environments\staging\site.example.tfvars .\terraform\environments\staging\site.tfvars
```

Edit `site.tfvars` and replace every example value:

| Setting | Value |
|---|---|
| `aws_region` | `us-east-1` |
| `environment` | `staging` |
| `site_bucket_name` | A globally unique website bucket name (see below) |
| `github_repository` | `<owner>@<owner-id>/<repo>@<repo-id>` |
| `github_oidc_provider_arn` | The provider ARN copied in section 1, step 4 |
| `alert_email` | A real mailbox you can read |

`github_repository` must match the subject GitHub puts in its OIDC token
exactly. This repository's tokens include the owner and repository IDs:
`repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:staging`.
With the plain `<owner>/<repo>` form, every deployment
fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity". To find
the IDs, open `https://api.github.com/repos/<owner>/<repo>` and use
`owner.id` and `id`.

Two mistakes still apply cleanly but break later:

- Leaving the example account `123456789012` in `github_oidc_provider_arn`
  makes every deployment fail the same way. Pasting the deploy role ARN there
  instead is rejected by AWS with `MalformedPolicyDocument`.
- Leaving `replace@example.com` in `alert_email` leaves the SNS subscription
  in `PendingConfirmation`, so alerts never arrive.

The website bucket is created by Terraform during apply and must differ from
the state bucket. S3 bucket names cannot contain underscores. This optional
command suggests a name; S3 checks that it is free when the bucket is
created:

```powershell
# Print a candidate name; this does not create a bucket.
"one-step-towards-ai-staging-site-$(Get-Date -Format 'yyyyMMddHHmmss')"
```

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

On a first run the plan should show **15 to add**: the website bucket and its
five settings (public access block, ownership, versioning, encryption,
policy), the CloudFront distribution, origin access control and headers
policy, the deploy role and its policy, the health check, the alarm, the SNS
topic and the email subscription. Review the account, resources, permissions
and charges. Only if the plan is correct, run:

```powershell
# Apply the reviewed plan to create or change AWS resources.
terraform apply staging.tfplan

# Show values needed for GitHub deployment and the website URL.
terraform output
```

Creating the CloudFront distribution takes several minutes. Keep the four
outputs: `website_url`, `site_bucket_name`, `deploy_role_arn` and
`aws_account_id`, which must be the workload account.

AWS then emails `alert_email` a subscription confirmation from AWS
Notifications; it may land in spam. Select **Confirm subscription** in it. The
link expires after three days; if it has, open **SNS > Subscriptions** in
`us-east-1`, select the subscription and choose **Request confirmation**.

Saved plans may contain sensitive data. If apply fails, inspect the error and
Terraform state; resources may already exist. After fixing the cause, create
and review a fresh plan rather than reusing the failed plan.

## 4. Publish using GitHub Actions

Push the project to the intended repository. GitHub runs workflows only from
`.github/workflows` at the repository root. Each push to `main` runs the
**Checks** workflow: repository rules, Terraform formatting and validation,
and a Windows PowerShell 5.1 parse of the scripts. It never touches AWS.

Create the `staging` environment and restrict it to `main`:

1. In the repository, open the **Settings** tab, then **Environments** in the
   left menu. Select **New environment**, enter `staging`, and select
   **Configure environment**.
2. Under **Deployment branches and tags**, change **No restriction** to
   **Selected branches and tags**.
3. Select **Add deployment branch or tag rule**, keep **Ref type: Branch**,
   enter `main`, and select **Add rule**. The page then shows
   "1 branch and 0 tags allowed".
4. Under **Environment variables**, select **Add environment variable**, enter
   the name and value, and select **Add variable**. Repeat for each row
   below. Add them to the environment, not as repository variables.

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `SITE_BUCKET` | Terraform output `site_bucket_name` |
| `WEBSITE_URL` | Terraform output `website_url`, without a trailing slash |
| `AWS_ROLE_ARN` | Terraform output `deploy_role_arn` |

Until the first deployment, the CloudFront URL returns `403 Forbidden`. That
is expected: the website bucket has no `index.html` yet.

To deploy, open the **Actions** tab and select **Deploy website** in the left
list. Select **Run workflow**, keep **Use workflow from: main** and the
environment `staging`, then select **Run workflow** in the form. The run
signs in to AWS as the deploy role, uploads `web/index.html`, and passes only
when the public page matches it; it takes under a minute. Deployments are
manual: a push never publishes the site. After pushing a fix, start a new run
rather than **Re-run jobs**: a re-run reuses the earlier commit, and a
production deployment requires the same commit to have succeeded in staging.

Then check, in the workload account with the console region set to
`us-east-1`:

1. The `website_url` shows the page.
2. **CloudWatch > Alarms > All alarms** shows `one-step-staging-unavailable`
   as **OK**. It can take a few minutes after the first deployment.
3. **SNS > Topics > one-step-staging-alerts**, **Subscriptions** tab, shows
   the email as **Confirmed**.

### If the deployment fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity"

GitHub reached AWS, but the deploy role's trust policy rejected its token.

1. Check that `github_oidc_provider_arn` in `site.tfvars` is this account's
   provider from section 1, not the example account or the role ARN.
2. Check that `github_repository` matches what GitHub sent. In the workload
   account, open **CloudTrail > Event history** with the region set to
   `us-east-1`. Change the lookup attribute to **Event name**, enter
   `AssumeRoleWithWebIdentity`, and open a failed event. In its event record,
   `userIdentity.userName` is the exact subject, such as
   `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:staging`.
   The part between `repo:` and `:environment:` is the value
   `github_repository` needs.
3. Correct `site.tfvars`, create and review a fresh plan (only the deploy
   role's trust policy should change), apply it, and start a new run.

## 5. Check costs and credits

The organization pays for all its accounts on one bill, so costs and credits
are in the **management account**, under **Billing and Cost Management**:

- **Bills**: this month's estimated charges. The **Charges by account** tab
  shows the workload account separately.
- **Credits**: each credit's amount used and remaining. **See complete list
  of services** shows what a credit covers; the AWS Free Tier credit covers
  Route 53, CloudFront, S3, CloudWatch and SNS.
- **Cost Explorer**: daily cost by service; filter **Linked account** to the
  workload account.

Estimates update about once every 24 hours, so a new deployment shows $0 at
first. Expected cost, from AWS's price list for `us-east-1`:

| Item | Price |
|---|---|
| Route 53 health check | The check uses two optional features, HTTPS and text matching, at $1.00 each per month for AWS endpoints or $2.00 each for other endpoints. The basic check is free for the first 50 checks of AWS endpoints, otherwise $0.75 per month. |
| CloudWatch alarm | $0.10 per month; the free tier includes 10 alarms. |
| CloudFront, S3, SNS email | Free tier or a few cents. |

About $2 to $6 per month in total, mostly the health check.

## 6. Clean up safely

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

Verify the resulting state and AWS resources: the apply must end with
`15 destroyed`, and `terraform state list` must then show no site resources.
A failed apply can leave resources not represented in state; after a partial
apply, inspect the state and AWS resources directly. Follow
the [full teardown checklist](operations.md#7-teardown-and-verify-one-environment).

Keep the state bucket, OIDC provider and the SCP entries from section 1 if
other projects may use them. Remove local `backend.hcl`, `site.tfvars`, and
saved plan files only after cleanup and verification; retain the example
files for the next run.
