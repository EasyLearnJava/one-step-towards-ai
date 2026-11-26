# Operations: staging and production

These are setup instructions, not a record that the resources already exist. Review all permissions, costs, and organization policies before deploying. Commands below use Windows PowerShell, starting from the project root unless stated otherwise.

## 1. Prerequisites

- Review the [illustrated deployment guide](staging-deployment-guide.html); its stage 1 covers the AWS CLI, Terraform and your AWS user. The [version 2 guide](staging-deployment-guide-v2.html) covers the API.
- For the API: Python 3.13 for local tests (see the [README](../README.md#run-the-api-on-your-pc)). Docker Desktop is optional: GitHub builds every image, including the first one when you [rebuild an environment](staging-deployment.md#rebuild-procedure-first-apply-in-a-new-environment).
- Have access to an AWS account, an approved infrastructure role, a GitHub repository, and GitHub environments.
- Configure AWS Budgets and alert recipients. Budgets alert on spending; they do not stop it.
- Prepare an AWS identity authorized to create and verify a state bucket. The bootstrap below creates a separate private, encrypted, versioned S3 bucket for each environment. Restrict access with IAM or organization policies and authorize the infrastructure role for the bucket, state and `.tflock` objects. Public-access blocking does not prevent access granted to other principals by IAM. For different accounts, provision a backend accessible to each account.
- Create or use the existing IAM OIDC provider for `https://token.actions.githubusercontent.com` in each AWS account. Its audience must include `sts.amazonaws.com`. There can be only one provider for this URL in an account; do not create a duplicate. Its ARN has the form `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`; it is not the deploy role ARN that Terraform outputs later.
- Select unique S3 website bucket names. Do not use the state bucket as a website bucket.
- Use separate staging and production AWS accounts where practical. In a shared account, use separate roles, buckets, distributions, and state keys, and restrict state access by environment.

The examples use `us-east-1` (N. Virginia) for the state and website buckets. If using an existing state bucket, set the backend region to that bucket's actual region. Monitoring also uses `us-east-1` because Route 53 health check metrics are published there. Changing a backend configuration does not move an existing state bucket or its state.

The API (ECR repository, Lambda function and its log group) uses `us-east-2` (Ohio), fixed in `versions.tf`. The organization's region policy blocks Lambda in `us-east-1`, and Lambda can pull images only from ECR in its own region. CloudFront is global and sends `/api/*` to the function, so the site keeps one address.

The site Terraform creates the GitHub deployment role; the infrastructure operator needs the separate permissions required to create and manage all configured resources. No AWS credentials belong in this repository.

The deployment role may only:

- upload `index.html` and `app.js` to the website bucket (`s3:PutObject`);
- push images to this environment's ECR repository, plus `ecr:GetAuthorizationToken`, which AWS does not allow to be limited to one repository;
- update this environment's Lambda function (`lambda:UpdateFunctionCode` and `lambda:GetFunctionConfiguration`).

The Lambda function's execution role may only write its own logs. The page's Content Security Policy allows scripts and requests only from the site itself (`script-src 'self'; connect-src 'self'`).

References: [S3 Terraform backend](https://developer.hashicorp.com/terraform/language/backend/s3), [GitHub OIDC in AWS](https://docs.github.com/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws), and [CloudFront OAC](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html).

## 2. Configure staging

First select the approved AWS credentials and check which account they use. For example, if you use IAM Identity Center:

```powershell
$env:AWS_PROFILE = "your-staging-profile"
aws sso login --profile $env:AWS_PROFILE
aws sts get-caller-identity
```

If you use another approved credential method, follow your administrator's instructions instead. Stop if the account is wrong; do not share credentials.

### Bootstrap the staging state bucket

From the V1 project root, replace the example account ID with your intended **12-digit AWS account ID** and choose the state bucket region. First you can preview the operation:

```powershell
.\scripts\bootstrap-state.ps1 -Environment staging -Region us-east-1 -ExpectedAccountId "123456789012" -WhatIf
```

When the account and region are correct, run the same command **without `-WhatIf`** and confirm the prompt:

```powershell
.\scripts\bootstrap-state.ps1 -Environment staging -Region us-east-1 -ExpectedAccountId "123456789012"
```

The script generates a unique bucket name; blocks public access; enables versioning and AES256 default encryption; adds a TLS-only bucket policy; verifies those settings and the region; then writes `terraform\environments\staging\backend.hcl`. If `backend.hcl` already exists, the script creates nothing new: it checks the bucket named there (owner account, region, public access block, versioning, encryption, HTTPS-only policy), prints each one as `[OK]` already applied or `[MISSING]`, and applies only the missing settings after you confirm. When everything is already applied it changes nothing. It never overwrites an existing backend configuration. The AWS CLI must have permissions for STS and the corresponding S3 create, put and get operations. This is separate from Terraform and can incur S3 charges. Terraform's S3 backend supplies encryption and lock-file settings from `versions.tf`.

The script checks the AWS account against the supplied ID and uses the credentials already selected in your shell; it never asks for keys. If creation or verification fails, it reports the bucket name that **may** exist. Inspect the account, bucket and any backend file before retrying or cleaning up; it never deletes a partial bucket automatically. Restrict IAM access to the state bucket separately, and do not share or commit Terraform state.

**Alternative:** If you already have an approved state bucket, copy `backend.example.hcl` to `backend.hcl` and configure the existing bucket, key and region manually. Then you can run the bootstrap with `-WhatIf` to check that bucket's settings without changing anything.

### Configure the site

Create the local site configuration, which is ignored by Git:

```powershell
Copy-Item .\terraform\environments\staging\site.example.tfvars .\terraform\environments\staging\site.tfvars
```

Edit `site.tfvars` with the website bucket, region, GitHub repository, existing OIDC provider ARN, and alert email. Keep `environment = "staging"`. Replace every example value; do not add credentials.

- `github_repository` must match the subject in GitHub's OIDC token exactly. This repository's tokens include the owner and repository IDs, so use `<owner>@<owner-id>/<repo>@<repo-id>`, not `<owner>/<repo>`. To find the IDs, open `https://api.github.com/repos/<owner>/<repo>` and use `owner.id` and `id`.
- `github_oidc_provider_arn` is the provider ARN from this account, not the deploy role ARN. AWS rejects the role ARN with `MalformedPolicyDocument`.
- A placeholder left in either of those two values still applies cleanly, but every deployment then fails with "Not authorized to perform sts:AssumeRoleWithWebIdentity"; see [troubleshooting](staging-deployment.md#if-the-deployment-fails-with-not-authorized-to-perform-stsassumerolewithwebidentity). A placeholder `alert_email` leaves the alert subscription unconfirmable.

## 3. Plan and apply staging

```powershell
Set-Location .\terraform\site
terraform init -reconfigure "-backend-config=..\environments\staging\backend.hcl"
terraform plan "-var-file=..\environments\staging\site.tfvars" "-out=staging.tfplan"
```

Review the plan, bucket names, account, role trust, and charges. Apply only if correct:

```powershell
terraform apply staging.tfplan
terraform output
```

The configuration has 25 resources: 15 for the website and 10 for the API. In a new or rebuilt environment, a plain first plan and apply fails: the Lambda function starts from the newest image in ECR, and a new repository is empty. Follow the [rebuild procedure](staging-deployment.md#rebuild-procedure-first-apply-in-a-new-environment): ECR and the deploy role only, a first image pushed by the Deploy workflow with **image only**, then everything else.

The saved plan can contain sensitive information; do not share or commit it. The site health alarm may report a failure until `index.html` is published. Confirm the SNS subscription email; no email alerts will arrive until confirmation.

Save these Terraform outputs for configuring the **staging** GitHub environment: `website_url`, `site_bucket_name`, `deploy_role_arn`, `api_ecr_repository_url` and `api_function_name`. Verify that `aws_account_id` is the intended account. The other outputs are `api_region` and `api_function_url`; the function URL is for checks only, because only CloudFront may call it.

## 4. Configure GitHub and deploy staging

Create GitHub environments named exactly `staging` and `production`. Restrict both to the `main` branch; protect production with required reviewers where your GitHub plan supports it. In this project all work goes directly on `main`, with no feature branches, so `Checks` runs on each push to `main`; wait for it to be green before deploying. The [staging guide](staging-deployment.md#4-publish-using-github-actions) gives the click path.

Set these GitHub **environment variables** for staging (not repository-wide values):

| Variable | Value |
|---|---|
| `AWS_REGION` | The region from staging `site.tfvars` |
| `SITE_BUCKET` | Terraform output `site_bucket_name` |
| `WEBSITE_URL` | Terraform output `website_url`, without a trailing slash |
| `AWS_ROLE_ARN` | Terraform output `deploy_role_arn` |
| `API_ECR_REPOSITORY` | Terraform output `api_ecr_repository_url` |
| `API_FUNCTION_NAME` | Terraform output `api_function_name`, for example `one-step-staging-api` |
| `API_REGION` | Optional, for reference: `us-east-2` (Terraform output `api_region`). The Deploy workflow reads the region from `API_ECR_REPOSITORY`. |

`API_ECR_REPOSITORY` contains the AWS account ID (`<account-id>.dkr.ecr.us-east-2.amazonaws.com/one-step-staging-api`); keep it in GitHub and never commit it.

Push the project to the intended GitHub repository. The `Checks` workflow runs repository rules (`scripts/check-repo.sh`), Terraform formatting and validation, a Windows PowerShell 5.1 parse of the scripts, and an `api` job: `python -m pytest`, a Docker build with the commit SHA (not pushed), and a run of the image that checks `/api/health` reports that SHA and `/api/hello` returns the welcome. It never touches AWS. From **Actions > Deploy website**, select `main` and `staging`, then run the workflow. Deployment is manual; a push does not publish automatically.

The workflow has two jobs. The `api` job builds the image on Linux with `--provenance=false` (the default provenance attestation turns the push into an image index, which Lambda rejects), pushes it to ECR tagged with the commit SHA, reads its digest, and updates the Lambda function to `<repository>@<digest>`. It waits with `aws lambda wait function-updated`, then checks that `<WEBSITE_URL>/api/health` reports this commit and `/api/hello` returns the welcome. The `deploy` job then uploads `web/app.js` and `web/index.html`, in that order, and checks both public responses byte-for-byte. The **image only** option stops after the push; it is for an environment whose function does not exist yet.

Inspect the CloudFront URL in a browser and select **Say hello to the API**. Check that direct anonymous S3 access is denied, that the function URL called directly returns 403, and that the health check and confirmed alert subscription work. An initially failing health check should recover after the first successful upload. The [staging guide](staging-deployment.md#test-the-api) lists the test commands and an [API troubleshooting table](staging-deployment.md#if-the-api-fails).

## 5. Set up production and promote

Return to the project root and create a separate production backend and site configuration. Select and verify the approved production AWS profile/account first; replace the example account ID and choose the region:

```powershell
Set-Location ..\..
.\scripts\bootstrap-state.ps1 -Environment production -Region us-east-1 -ExpectedAccountId "123456789012"
Copy-Item .\terraform\environments\production\site.example.tfvars .\terraform\environments\production\site.tfvars
```

Alternatively configure an existing production backend manually using its example file. Fill in production `site.tfvars`, replacing every example value:

- `site_bucket_name`: a new globally unique production bucket, different from the staging bucket.
- `github_repository`: the same value as staging, `<owner>@<owner-id>/<repo>@<repo-id>`. Terraform appends `:environment:production`, so only the `production` GitHub environment can assume the production role.
- `github_oidc_provider_arn`: the provider in the production account. A separate production account needs its own provider (section 1), and the ARN carries that account's ID.
- `alert_email`: a real mailbox; confirm the SNS subscription after apply.

A separate, new production account may also need its own CloudFront account verification before apply; see the [staging guide](staging-deployment.md#1-prepare-aws). If the organization's region SCP is attached at the root, the `us-east-1` exemptions added for staging already cover production.

Repeat the staging initialization, plan, and apply commands with `production` replacing `staging`, including `terraform init -reconfigure` before changing backends. A new production environment needs the [rebuild procedure](staging-deployment.md#rebuild-procedure-first-apply-in-a-new-environment), with `production` in place of `staging` (repository `one-step-production-api`). In the plan, check that the deploy role's trust `sub` reads `repo:<owner>@<owner-id>/<repo>@<repo-id>:environment:production`. Configure the GitHub environment variables (`AWS_REGION`, `SITE_BUCKET`, `WEBSITE_URL`, `AWS_ROLE_ARN`, `API_ECR_REPOSITORY`, `API_FUNCTION_NAME`, and optionally `API_REGION`) on the `production` environment from the production outputs.

Production has not been built for version 2 yet; promotion to production is planned for step 6.

Before deploying, compare the commit in the successful staging run with the current `main` commit. If they differ, deploy and verify the current `main` commit in staging first. Start a new staging run for it; **Re-run jobs** reuses the earlier run's commit. Then run the deployment workflow for `production` and approve it through the protected GitHub environment. The workflow also checks the GitHub deployment API for a successful staging deployment of that exact commit; a missing, failed, or inactive deployment blocks production. This check runs at the start of the `api` job, before it signs in to AWS, so a blocked run pushes no image and changes nothing. Verify the production page, API and monitoring independently.

## 6. Operate and recover

- **Rollback:** revert the change in Git, push the revert to `main`, deploy and verify that commit in staging, then approve and deploy it to production. S3 versioning is an additional recovery mechanism; direct restoration needs separate authorized permissions. For a quick API-only rollback, see below.
- **Alerts:** the Route 53 HTTPS health check searches the page for `One Step At A Time`. If the title changes, update the health-check string as part of the same release. The alarm monitors Route 53 health metrics in `us-east-1`. It checks the page only, not the API; the Deploy workflow checks the API on each release.
- **Caching:** CloudFront caching is disabled and the page has `Cache-Control: no-cache`. The `/api/*` route also uses `Managed-CachingDisabled`, and `/api/hello` sends `Cache-Control: no-store`. When adding versioned assets, design and test a separate caching strategy before changing this behavior.
- **Logs:** website access logging is not enabled by this configuration. Decide on privacy, retention, access, and cost before enabling it. The API writes its logs to CloudWatch Logs in `us-east-2`, kept 14 days (see below).
- **Destruction:** the website bucket has `force_destroy = true` and the ECR repository has `force_delete = true` for a disposable deployment. Destroying them permanently deletes the bucket's objects, all versions and delete markers, and every API image. Follow the checklist below; do not delete remote state before verification.
- **Costs:** S3 requests/storage, CloudFront, Route 53 health checks, SNS, CloudWatch, Lambda, ECR storage and CloudWatch Logs may incur charges. The API is expected to add well under $1 a month until AI calls arrive; check the [cost estimate](staging-deployment.md#5-check-costs-and-credits). Review usage and alerts regularly.
- **Future login:** the website and the API are public through CloudFront, with no login. OAC protects the bucket and function URL origins, not user data. The function's reserved concurrency of 5 caps cost and abuse. Before any AI call (step 3), add login or a rate limit and a budget alarm. Private data requires separate authentication and authorization.

### API: live version, logs and rollback

**Which commit is live.** `/api/health` reports the commit SHA of the running image:

```powershell
curl.exe -sS "https://d****.cloudfront.net/api/health"
```

Use your `website_url` in place of the example address. Compare the `version` with `git log --oneline -5`.

**Logs.** The log group is `/aws/lambda/one-step-<environment>-api` in `us-east-2`, kept 14 days. In the console, open **CloudWatch > Log groups** with the region set to `us-east-2`. From the command line, with the infrastructure credentials:

```powershell
aws logs tail /aws/lambda/one-step-staging-api --region us-east-2 --since 1h
```

Each request ends with a `REPORT` line: duration, billed duration, memory size and memory used. A cold start adds `Init Duration`, the time to start the image and the app.

**Rollback the API.** Two ways:

1. Through GitHub, preferred: open an earlier successful **Deploy website** run (from version 2 on) and select **Re-run all jobs**. A re-run uses that run's commit, so it rebuilds and ships the older image and page, and checks them.
2. Directly, with the infrastructure credentials: point the function at an older image still in ECR. The lifecycle rule keeps only the newest 5 images.

   ```powershell
   # List images, newest last, with their commit tags and digests.
   aws ecr describe-images --repository-name one-step-staging-api --region us-east-2 --query "sort_by(imageDetails,&imagePushedAt)[].[imageTags[0],imageDigest,imagePushedAt]" --output table

   # Switch the function to the chosen image and wait for the update.
   aws lambda update-function-code --function-name one-step-staging-api --region us-east-2 --image-uri "<account-id>.dkr.ecr.us-east-2.amazonaws.com/one-step-staging-api@sha256:<older-digest>"
   aws lambda wait function-updated --function-name one-step-staging-api --region us-east-2
   ```

   Then check `/api/health` shows the older commit. This changes the API only, not the page. Terraform ignores image changes, so it reports no drift. The next Deploy run replaces it again.

## 7. Teardown and verify one environment

**Destructive operation:** This permanently deletes the selected environment's website and all object versions, the API function, and every image in its ECR repository. Back up anything needed and stop if the account, environment, state, or plan is unexpected. Never destroy a shared state bucket or shared OIDC provider without checking every dependent project and environment.

Use the approved infrastructure role, not the restricted GitHub deployment role. It needs permissions to remove the resources, including listing and deleting S3 object versions. A permission error is **not** proof that a resource is gone.

### Checklist: destroy

Repeat these steps separately for each deployed environment. The example uses **staging**, starting from the project root:

1. [ ] Disable or pause deployments for this environment so a workflow cannot republish during teardown. Save any needed data.
2. [ ] Log in with the approved profile, run `aws sts get-caller-identity`, and confirm the account. Check the backend file's state bucket and key; they must belong to this environment.
3. [ ] Select the correct state:

   ```powershell
   Set-Location .\terraform\site
   terraform init -reconfigure "-backend-config=..\environments\staging\backend.hcl"
   terraform state list
   ```

4. [ ] If this environment was applied before `force_destroy = true` was added, review and perform a **normal** `terraform plan` and `terraform apply` with its `site.tfvars` first. The AWS provider needs a successful apply to record this setting before destroy. Do not apply a plan containing unexpected changes.
5. [ ] Create and review a destroy plan:

   ```powershell
   terraform plan -destroy "-var-file=..\environments\staging\site.tfvars" "-out=staging-destroy.tfplan"
   terraform show staging-destroy.tfplan
   ```

   Confirm every planned deletion belongs to the intended account and environment. The saved plan may contain sensitive data; do not commit it. **Do not proceed** if the plan fails or contains unexpected resources.
6. [ ] Only after reviewing and accepting permanent deletion, apply that saved plan:

   ```powershell
   terraform apply staging-destroy.tfplan
   ```

   CloudFront deletion can take time. If Terraform reports an error, resolve it and re-plan; do not assume teardown finished.

   The ECR repository has `force_delete = true`, so it is deleted with its images; nothing needs deleting first. Lambda added its own repository policy, `LambdaECRImageRetrievalPolicy`, when the function was created. Terraform does not manage it, and it disappears with the repository.

### Checklist: verify after destroy

1. [ ] Confirm the apply ended with `Apply complete! Resources: 0 added, 0 changed, 25 destroyed.`, then check Terraform's record:

   ```powershell
   terraform state list
   ```

   Terraform deletes each resource and waits for AWS to confirm; if a deletion fails, the apply stops with an error and that resource stays in the state. `terraform state list` should show no managed site resources. Data sources may remain; review unexpected entries rather than deleting state.
2. [ ] Independently review CloudFront, S3, Route 53 health checks, CloudWatch and SNS in AWS (the monitoring region is `us-east-1`), and ECR, Lambda and the `/aws/lambda/one-step-<environment>-api` log group in `us-east-2`. Include resources created manually or by a failed apply, which the Terraform state does not record.
3. [ ] Repeat for **production**, if deployed, using its own profile, `backend.hcl`, `site.tfvars` and plan. Do not remove the backend while any environment still uses it.
4. [ ] Review the separate state bucket, including state and lock-file **versions**, delete markers, and incomplete multipart uploads. If it is exclusively owned by this project and all environments are finished, use an approved, reviewed S3 cleanup procedure to delete its contents and then the bucket. This is outside the site Terraform state. If shared, retain it and remove only explicitly approved project-owned state objects and versions.
5. [ ] Review the existing GitHub OIDC provider, AWS Budgets, alerts, and any manually created resources. Remove only those exclusively owned by this project and no longer needed; never delete a shared provider or budget blindly.
6. [ ] Review AWS Billing/Cost Explorer over the following days for all relevant accounts and regions. AWS may report delayed charges or already-incurred usage. An empty Terraform state does **not** guarantee a zero bill or reveal resources Terraform never managed.

If an apply failed partway, inspect the Terraform state and AWS consoles before attempting cleanup.

To build the environment again later, follow the [rebuild procedure](staging-deployment.md#rebuild-procedure-first-apply-in-a-new-environment); a plain first apply fails while the ECR repository is empty.
