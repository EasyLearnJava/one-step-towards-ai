# Staging deployment: step by step

These instructions use Windows PowerShell, an S3 state bucket and website
bucket in N. Virginia (`us-east-1`), the API (ECR repository and Lambda
function) in Ohio (`us-east-2`), and the GitHub repository
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
| Workload account | Everything this guide creates: state bucket, OIDC provider, website bucket, CloudFront, deploy role, health check, alarm and SNS topic, and for the API the ECR repository, Lambda function and its log group. The AWS CLI and Terraform must use this account. |
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

   The same policy blocks Lambda in `us-east-1` and allows everything in
   `us-east-2`. That is why the API runs in `us-east-2`: do not add Lambda
   to the exemption list. Lambda can pull images only from ECR in its own
   region, so the ECR repository is in `us-east-2` too. CloudFront is
   global, so the site keeps one address. `us-east-2` needs no SCP change.

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

The configuration has **25 resources** in total:

- 15 for the website (version 1): the website bucket and its five settings
  (public access block, ownership, versioning, encryption, policy), the
  CloudFront distribution, origin access control and headers policy, the
  deploy role and its policy, the health check, the alarm, the SNS topic and
  the email subscription.
- 10 for the API (version 2), in `us-east-2` except the IAM role, its
  policy and the CloudFront access control, which are global: the ECR
  repository and its
  lifecycle policy (keep the newest 5 images); the log group, execution
  role, role policy, Lambda function and function URL; the Lambda-type
  origin access control and two invoke permissions for CloudFront.

In a **new or rebuilt environment**, a plain plan and apply cannot create
them all at once. Follow the rebuild procedure below instead. In an
environment that already has an image in ECR, review the plan and, only if
it is correct, run:

```powershell
# Apply the reviewed plan to create or change AWS resources.
terraform apply staging.tfplan

# Show values needed for GitHub deployment and the website URL.
terraform output
```

### Rebuild procedure: first apply in a new environment

The Lambda function starts from the newest image in ECR, which Terraform
reads with the `aws_ecr_image` data source. A new repository is empty, so a
plain first apply fails at that data source. The CloudFront distribution
depends on the function, so it cannot be created first either. The deploy
role does not: its policy builds the function's ARN from the function's
name, so the role can exist before the function. Work in this order:

1. **ECR repository and deploy role only.** From `terraform\site`:

   ```powershell
   # Plan only these two; Terraform adds what they need (the repository,
   # the website bucket and the deploy role).
   terraform plan "-var-file=..\environments\staging\site.tfvars" "-target=aws_ecr_lifecycle_policy.api" "-target=aws_iam_role_policy.deploy" "-out=staging.tfplan"
   terraform show staging.tfplan
   terraform apply staging.tfplan
   ```

   The plan shows **5 to add**: the website bucket, the ECR repository, its
   lifecycle policy, the deploy role and its policy. Terraform warns that
   `-target` is for exceptional cases; that is expected here.

2. **First image, from GitHub.** Get the repository URL (`terraform output`
   may not list it after a targeted apply):

   ```powershell
   # <account-id>.dkr.ecr.us-east-2.amazonaws.com/one-step-staging-api
   aws ecr describe-repositories --repository-names one-step-staging-api --region us-east-2 --query "repositories[0].repositoryUri" --output text
   ```

   In GitHub, set `API_ECR_REPOSITORY` to that URL and check
   `AWS_ROLE_ARN` (section 4; the role name is unchanged, so the ARN
   usually is too). Enable the Deploy workflow if it was disabled, then run
   it with **image only** ticked. ECR then lists one image tagged with the
   commit SHA. No Docker is needed on your PC.

3. **Everything else.** From `terraform\site`, run the plan, show and apply
   commands at the start of this section, without `-target`. The plan shows
   **20 to add**. Creating the CloudFront distribution takes several
   minutes.

4. **GitHub variables.** Set the variables in section 4 (`API_REGION` is
   optional).

5. **Confirm and deploy.** Confirm the SNS email (below), then run the
   Deploy workflow in full, without **image only** (section 4).

This order follows from the Terraform code; it has not yet been run end to
end. The first staging build went piece by piece instead: repository
(TODO piece 2.6), Deploy with **image only** (2.7), Lambda function (2.8),
CloudFront route and permissions (2.9).

Keep the outputs: `website_url`, `site_bucket_name`, `deploy_role_arn` and
`aws_account_id`, which must be the workload account; and for the API
`api_ecr_repository_url`, `api_region`, `api_function_name` and
`api_function_url`. The repository URL contains the account ID: never commit
it.

AWS then emails `alert_email` a subscription confirmation from AWS
Notifications; it may land in spam. Select **Confirm subscription** in it. The
link expires after three days; if it has, open **SNS > Subscriptions** in
`us-east-1`, select the subscription and choose **Request confirmation**.

Saved plans may contain sensitive data. If apply fails, inspect the error and
Terraform state; resources may already exist. After fixing the cause, create
and review a fresh plan rather than reusing the failed plan.

## 4. Publish using GitHub Actions

Push the project to the intended repository. GitHub runs workflows only from
`.github/workflows` at the repository root. All work goes directly on
`main`; there are no feature branches. Each push to `main` runs the
**Checks** workflow: repository rules, Terraform formatting and validation,
a Windows PowerShell 5.1 parse of the scripts, and the `api` job. The `api`
job runs the tests with `python -m pytest`, builds the Docker image with the
commit SHA (it does not push it), starts it, and checks that `/api/health`
reports that SHA and `/api/hello` returns the welcome. Checks never touches
AWS.

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
| `API_ECR_REPOSITORY` | Terraform output `api_ecr_repository_url` |
| `API_FUNCTION_NAME` | Terraform output `api_function_name`, for example `one-step-staging-api` |
| `API_REGION` | Optional, for reference: `us-east-2` (Terraform output `api_region`) |

`API_ECR_REPOSITORY` has the form
`<account-id>.dkr.ecr.us-east-2.amazonaws.com/one-step-staging-api`. It
contains the account ID: keep it in GitHub, never in the repository. The
Deploy workflow reads the API region from this URL, so it does not need
`API_REGION`; keeping it does no harm.

Until the first deployment, the CloudFront URL returns `403 Forbidden`. That
is expected: the website bucket has no `index.html` yet.

To deploy, open the **Actions** tab and select **Deploy website** in the left
list. Select **Run workflow**, keep **Use workflow from: main** and the
environment `staging`, leave **image only** unticked, then select **Run
workflow** in the form. The run has two jobs, both signed in to AWS as the
deploy role:

1. **api**: for production, first checks that this commit has a successful
   staging deployment. Then builds the image on Linux with
   `--provenance=false`, pushes it to ECR tagged with the commit SHA, and
   reads its digest. It updates the Lambda function to
   `<repository>@<digest>`, waits with `aws lambda wait function-updated`,
   and checks that `<WEBSITE_URL>/api/health` reports this commit and
   `/api/hello` returns the welcome.
2. **deploy**: uploads `web/app.js`, then `web/index.html`, and passes only
   when the public copies of both match.

A full run takes a few minutes. With **image only** ticked, the run stops
after the push; that is for an environment whose function does not exist
yet. Deployments are manual: a push never publishes the site or the API.
After pushing a fix, start a new run rather than **Re-run jobs**: a re-run
reuses the earlier commit, and a production deployment requires the same
commit to have succeeded in staging.

Then check, in the workload account with the console region set to
`us-east-1`:

1. The `website_url` shows the page. **Say hello to the API** shows the
   welcome, and the browser console shows no CSP errors.
2. **CloudWatch > Alarms > All alarms** shows `one-step-staging-unavailable`
   as **OK**. It can take a few minutes after the first deployment.
3. **SNS > Topics > one-step-staging-alerts**, **Subscriptions** tab, shows
   the email as **Confirmed**.

### Test the API

From `terraform\site`, with the infrastructure credentials:

```powershell
# Terraform output website_url, for example https://d****.cloudfront.net
$site = terraform output -raw website_url

# Both return JSON; version is the deployed commit SHA.
curl.exe -sS "$site/api/health"
curl.exe -sS "$site/api/hello"

# Any other path under /api returns 404.
curl.exe -sS -o NUL -w "%{http_code}`n" "$site/api/other"

# The function URL called directly must return 403: only CloudFront may call it.
curl.exe -sS -o NUL -w "%{http_code}`n" "$(terraform output -raw api_function_url)api/health"
```

In the console, with the region set to `us-east-2`, **Lambda > Functions >
one-step-staging-api** shows the function as an image with 512 MB, a 15 s
timeout, `x86_64` and reserved concurrency 5.

### If the API fails

| What you see | Cause | Fix |
|---|---|---|
| `docker build` on your PC: `CERTIFICATE_VERIFY_FAILED` from `pip` | Zscaler or another HTTPS-inspecting proxy re-signs HTTPS | Build with `--secret id=ca,src=<path-to-ca-bundle.pem>` (see the README). |
| ECR shows an image index plus an attestation for one push, and Lambda rejects it | The build added a provenance attestation | Build with `--provenance=false` (the Deploy workflow does) and push again. |
| Checks or Deploy: `429 Too Many Requests`, `Data limit exceeded`, from `public.ecr.aws` | GitHub's shared runner IP addresses pull the Lambda Web Adapter image without logging in, and hit AWS's anonymous limit | Re-run the failed job; it reuses the same commit, which is fine here. Open issue: see [Open issues](staging-deployment-guide-v2.html#issue-429) in the version 2 guide. |
| `/api/hello` on the site returns S3 `AccessDenied` XML | The `/api/*` route is not applied yet, or CloudFront is still rolling it out | Check that the last apply included the distribution change, and wait a few minutes. |
| `403` with a JSON body from Lambda, through CloudFront | A CloudFront invoke permission is missing | Run `aws lambda get-policy --function-name one-step-staging-api --region us-east-2`. It must list both `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction` for `cloudfront.amazonaws.com`, limited to this distribution. |
| The function URL called directly does not return 403 | The function URL's auth type is not `AWS_IAM` | `aws lambda get-function-url-config --function-name one-step-staging-api --region us-east-2` must show `AWS_IAM`; re-apply Terraform. |
| `uvicorn --reload` on your PC keeps serving old code | On Windows, a server started in a background shell does not get the restart signal | Stop the server and start it again. |

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
| Lambda (API) | Always free each month: 1 million requests and 400,000 GB-seconds of compute. A hello API stays far below that. |
| ECR (API images) | About $0.10 per GB per month. Each image is about 65 MB and the lifecycle rule keeps 5: a few cents. |
| CloudWatch Logs (API) | Pay per GB ingested and stored; a few lines per request, kept 14 days: tiny. |

About $2 to $6 per month for the version 1 pieces, mostly the health check.
The API should add well under $1 a month until step 3 adds AI calls. These
are estimates: check the AWS pricing pages for Lambda, ECR and CloudWatch
before relying on them. The API is in `us-east-2`, so filter Cost Explorer
by region if you want its share.

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
`25 destroyed`, and `terraform state list` must then show no site resources.
A failed apply can leave resources not represented in state; after a partial
apply, inspect the state and AWS resources directly. Follow
the [full teardown checklist](operations.md#7-teardown-and-verify-one-environment).

The ECR repository has `force_delete = true`, so the destroy removes it with
all its images; nothing needs deleting first. When the function was created,
Lambda added its own repository policy, `LambdaECRImageRetrievalPolicy`.
Terraform does not manage it; it disappears with the repository. Check
`us-east-2` as well as `us-east-1` afterwards: ECR, Lambda and the
`/aws/lambda/one-step-staging-api` log group must be gone. To build the
environment again, use the
[rebuild procedure](#rebuild-procedure-first-apply-in-a-new-environment).

Keep the state bucket, OIDC provider and the SCP entries from section 1 if
other projects may use them. Remove local `backend.hcl`, `site.tfvars`, and
saved plan files only after cleanup and verification; retain the example
files for the next run.
