# Operations: staging and production

These are setup instructions, not a record that the resources already exist. Review all permissions, costs, and organization policies before deploying. Commands below use Windows PowerShell, starting from the project root unless stated otherwise.

## 1. Prerequisites

- Review the [V1 static website guide](step-01-static-website.pdf) and, if V0 is available alongside V1, the [V0 prerequisites PDF](../../v0-prerequisites/docs/aws-and-terraform-prerequisites.pdf).
- Have access to an AWS account, an approved infrastructure role, a GitHub repository, and GitHub environments.
- Configure AWS Budgets and alert recipients. Budgets alert on spending; they do not stop it.
- Prepare an AWS identity authorized to create and verify a state bucket. The bootstrap below creates a separate private, encrypted, versioned S3 bucket for each environment. Restrict access with IAM or organization policies and authorize the infrastructure role for the bucket, state and `.tflock` objects. Public-access blocking does not prevent access granted to other principals by IAM. For different accounts, provision a backend accessible to each account.
- Create or use the existing IAM OIDC provider for `https://token.actions.githubusercontent.com` in each AWS account. Its audience must include `sts.amazonaws.com`. There can be only one provider for this URL in an account; do not create a duplicate. Its ARN has the form `arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com`; it is not the deploy role ARN that Terraform outputs later.
- Select unique S3 website bucket names. Do not use the state bucket as a website bucket.
- Use separate staging and production AWS accounts where practical. In a shared account, use separate roles, buckets, distributions, and state keys, and restrict state access by environment.

The examples use `us-east-1` (N. Virginia) for the state and website buckets. If using an existing state bucket, set the backend region to that bucket's actual region. Monitoring also uses `us-east-1` because Route 53 health check metrics are published there. Changing a backend configuration does not move an existing state bucket or its state.

The site Terraform creates the GitHub deployment role; the infrastructure operator needs the separate permissions required to create and manage all configured resources. No AWS credentials belong in this repository.

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

- `github_repository` must match the subject in GitHub's OIDC token exactly. This repository's tokens include the owner and repository IDs, so use `EasyLearnJava@6612328/one-step-towards-ai@1470924284`, not `EasyLearnJava/one-step-towards-ai`. For another repository, open `https://api.github.com/repos/OWNER/REPO` and use `owner.id` and `id`.
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

The saved plan can contain sensitive information; do not share or commit it. The site health alarm may report a failure until `index.html` is published. Confirm the SNS subscription email; no email alerts will arrive until confirmation.

Save these Terraform outputs for configuring the **staging** GitHub environment: `website_url`, `site_bucket_name`, and `deploy_role_arn`. Verify that `aws_account_id` is the intended account.

Capture the deployed resources **before any teardown**, while still in `terraform\site`:

```powershell
..\..\scripts\check-site-resources.ps1 -Mode capture -Inventory ..\..\staging.inventory.json
```

The inventory is local and ignored by Git. Keep it until teardown has been verified; it contains resource identifiers, not credentials. The command refuses to overwrite an existing file. Capture a separate inventory for production after applying it, using `production.inventory.json`. If resources change, capture a new inventory under a new name. The checker fails if the AWS CLI account differs from the account recorded in the Terraform state or if the expected inventory is incomplete.

## 4. Configure GitHub and deploy staging

Create GitHub environments named exactly `staging` and `production`. Restrict both to the `main` branch; protect production with required reviewers where your GitHub plan supports it. Protect `main` with pull request review and required checks. The [staging guide](staging-deployment.md#4-publish-using-github-actions) gives the click path.

Set these GitHub **environment variables** for staging (not repository-wide values):

| Variable | Value |
|---|---|
| `AWS_REGION` | The region from staging `site.tfvars` |
| `SITE_BUCKET` | Terraform output `site_bucket_name` |
| `WEBSITE_URL` | Terraform output `website_url`, without a trailing slash |
| `AWS_ROLE_ARN` | Terraform output `deploy_role_arn` |

Push the project to the intended GitHub repository. The checks workflow validates the site and Terraform. From **Actions > Deploy website**, select `main` and `staging`, then run the workflow. Deployment is manual; a push does not publish automatically.

The workflow publishes only `web/index.html` and checks the public response byte-for-byte. Inspect the CloudFront URL in a browser, check that direct anonymous S3 access is denied, and verify that the health check and confirmed alert subscription work. An initially failing health check should recover after the first successful upload.

## 5. Set up production and promote

Return to the project root and create a separate production backend and site configuration. Select and verify the approved production AWS profile/account first; replace the example account ID and choose the region:

```powershell
Set-Location ..\..
.\scripts\bootstrap-state.ps1 -Environment production -Region us-east-1 -ExpectedAccountId "123456789012"
Copy-Item .\terraform\environments\production\site.example.tfvars .\terraform\environments\production\site.tfvars
```

Alternatively configure an existing production backend manually using its example file. Fill in production `site.tfvars`, replacing every example value:

- `site_bucket_name`: a new globally unique production bucket, different from the staging bucket.
- `github_repository`: the same value as staging, `EasyLearnJava@6612328/one-step-towards-ai@1470924284`. Terraform appends `:environment:production`, so only the `production` GitHub environment can assume the production role.
- `github_oidc_provider_arn`: the provider in the production account. A separate production account needs its own provider (section 1), and the ARN carries that account's ID.
- `alert_email`: a real mailbox; confirm the SNS subscription after apply.

A separate, new production account may also need its own CloudFront account verification before apply; see the [staging guide](staging-deployment.md#1-prepare-aws). If the organization's region SCP is attached at the root, the `us-east-1` exemptions added for staging already cover production.

Repeat the staging initialization, plan, and apply commands with `production` replacing `staging`, including `terraform init -reconfigure` before changing backends. In the plan, check that the deploy role's trust `sub` reads `repo:EasyLearnJava@6612328/one-step-towards-ai@1470924284:environment:production`. Configure the four GitHub environment variables (`AWS_REGION`, `SITE_BUCKET`, `WEBSITE_URL`, `AWS_ROLE_ARN`) on the `production` environment from the production outputs.

Before deploying, compare the commit in the successful staging run with the current `main` commit. If they differ, deploy and verify the current `main` commit in staging first. Start a new staging run for it; **Re-run jobs** reuses the earlier run's commit. Then run the deployment workflow for `production` and approve it through the protected GitHub environment. The workflow also checks the GitHub deployment API for a successful staging deployment of that exact commit; a missing, failed, or inactive deployment blocks production. Verify the production page and monitoring independently.

## 6. Operate and recover

- **Rollback:** revert the change in Git, merge the revert to `main`, deploy and verify that commit in staging, then approve and deploy it to production. S3 versioning is an additional recovery mechanism; direct restoration needs separate authorized permissions.
- **Alerts:** the Route 53 HTTPS health check searches the page for `One Step At A Time`. If the title changes, update the health-check string as part of the same release. The alarm monitors Route 53 health metrics in `us-east-1`.
- **Caching:** CloudFront caching is disabled and the page has `Cache-Control: no-cache`. When adding versioned assets, design and test a separate caching strategy before changing this behavior.
- **Logs:** website access logging is not enabled by this configuration. Decide on privacy, retention, access, and cost before enabling it.
- **Destruction:** the website bucket has `force_destroy = true` for a disposable deployment. Destroying it permanently deletes its objects, all versions, and delete markers. Follow the checklist below; do not delete remote state before verification.
- **Costs:** S3 requests/storage, CloudFront, Route 53 health checks, SNS, and CloudWatch may incur charges. Review usage and alerts regularly.
- **Future login:** the website is public. OAC protects the bucket origin, not user data. Login, private data, and APIs require separate authentication and authorization.

## 7. Teardown and verify one environment

**Destructive operation:** This permanently deletes the selected environment's website and all object versions. Back up anything needed and stop if the account, environment, state, or plan is unexpected. Never destroy a shared state bucket or shared OIDC provider without checking every dependent project and environment.

Use the approved infrastructure role, not the restricted GitHub deployment role. It needs permissions to remove the resources, including listing and deleting S3 object versions, and the AWS list permissions used by the checker. Permission errors or failed checks are **not** proof that resources are gone.

### Checklist: capture and destroy

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
5. [ ] Capture a fresh inventory if you have not already done so, using a unique filename:

   ```powershell
   ..\..\scripts\check-site-resources.ps1 -Mode capture -Inventory ..\..\staging.inventory.json
   ```

   Review its account and resource IDs. Keep this file: Terraform removes resources from state as it destroys them.
6. [ ] Create and review a destroy plan:

   ```powershell
   terraform plan -destroy "-var-file=..\environments\staging\site.tfvars" "-out=staging-destroy.tfplan"
   terraform show staging-destroy.tfplan
   ```

   Confirm every planned deletion belongs to the intended account and environment. The saved plan may contain sensitive data; do not commit it. **Do not proceed** if the plan fails or contains unexpected resources.
7. [ ] Only after reviewing and accepting permanent deletion, apply that saved plan:

   ```powershell
   terraform apply staging-destroy.tfplan
   ```

   CloudFront deletion can take time. If Terraform reports an error, resolve it and re-plan; do not assume teardown finished.

### Checklist: verify after destroy

1. [ ] While using the same account, run the checker with the inventory captured before destroy:

   ```powershell
   ..\..\scripts\check-site-resources.ps1 -Mode verify -Inventory ..\..\staging.inventory.json
   terraform state list
   ```

   The checker lists each resource parent as `NOT FOUND` or `REMAINS` and exits with an error if one remains or an AWS query fails. It checks the website bucket (and hence its bucket-specific settings), CloudFront distribution, origin access control, headers policy, deployment role (and its inline policy), Route 53 health check, SNS topic and subscriptions, and CloudWatch alarm. `terraform state list` should show no managed site resources. Data sources may remain; review unexpected entries rather than deleting state.
2. [ ] Wait and retry if AWS is still converging. Independently review CloudFront, S3, Route 53 health checks, CloudWatch and SNS in AWS, including resources created manually or by a failed apply before inventory capture. The checker only checks the captured IDs in the selected account and the monitoring region `us-east-1`; it does not search for unrelated resources or other regions/accounts.
3. [ ] Repeat for **production**, if deployed, using its own profile, `backend.hcl`, `site.tfvars`, plan, and inventory. Do not remove the backend while any environment still uses it.
4. [ ] Review the separate state bucket, including state and lock-file **versions**, delete markers, and incomplete multipart uploads. If it is exclusively owned by this project and all environments are finished, use an approved, reviewed S3 cleanup procedure to delete its contents and then the bucket. This is outside the site Terraform state. If shared, retain it and remove only explicitly approved project-owned state objects and versions.
5. [ ] Review the existing GitHub OIDC provider, AWS Budgets, alerts, and any manually created resources. Remove only those exclusively owned by this project and no longer needed; never delete a shared provider or budget blindly.
6. [ ] Review AWS Billing/Cost Explorer over the following days for all relevant accounts and regions. AWS may report delayed charges or already-incurred usage. A successful checker does **not** guarantee a zero bill or find resources outside its scope.

The inventory is a point-in-time record, not a discovery tool for the whole account. If an apply fails before capture, inspect the Terraform state and AWS consoles before attempting cleanup.
