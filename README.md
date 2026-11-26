# One Step At A Time

From curiosity to capable AI agents - one step at a time.

A single HTML page, designed to be delivered through CloudFront from a private S3 bucket. There is no application server, Docker image, database, or AI service in this first release.

## Project structure

```text
one-step-towards-ai\
  web\
    index.html
  terraform\
    site\
      versions.tf
      main.tf
      variables.tf
      outputs.tf
      .terraform.lock.hcl
    environments\
      staging\
        backend.example.hcl
        site.example.tfvars
      production\
        backend.example.hcl
        site.example.tfvars
  docs\
    staging-deployment-guide.html
    staging-deployment.md
    operations.md
    coding-agent-prompt.md
  scripts\
    bootstrap-state.ps1
    check-repo.sh
  .github\
    workflows\
      checks.yml
      deploy.yml
  .gitattributes
  .gitignore
  README.md
```

Only `web/index.html` is published. The guides are in `docs`.

Commands below start from the repository root, the `one-step-towards-ai` folder. GitHub only runs workflows from `.github/workflows` at the repository root.

## Start here

1. Open the [illustrated deployment guide](docs/staging-deployment-guide.html) (HTML, with screenshots).
2. Open `web\index.html` in a browser to preview the page.
3. Read the [operations guide](docs/operations.md) before provisioning AWS or setting up GitHub.
   For a manual staging setup, see the [step-by-step deployment guide](docs/staging-deployment.md).
4. Run the local checks, the same ones the `Checks` workflow runs on GitHub:

   ```powershell
   terraform fmt -check -recursive terraform
   & "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh
   ```

   `check-repo.sh` needs Git Bash. Plain `bash` in PowerShell usually starts WSL instead, so call Git Bash's `bash.exe` as shown, or run `bash scripts/check-repo.sh` inside a Git Bash window. It prints six `[OK]` lines and `All repository checks passed.`

The [operations guide](docs/operations.md) explains how to bootstrap a private state bucket with `scripts\bootstrap-state.ps1` before initializing the site backend. The script creates billable AWS resources only after confirmation; it does not deploy the site.

The Terraform AWS provider lock file is committed so different machines and CI use the same provider version. `terraform init -backend=false -lockfile=readonly` followed by `terraform validate` checks the infrastructure syntax without accessing AWS state.

## Architecture

```text
Browser -- HTTPS --> CloudFront -- signed origin request --> private S3 bucket
```

Staging and production have separate site buckets, CloudFront distributions, deployment roles, and state keys. CloudFront caching is disabled initially; the deployment uploads only `index.html` and checks that the public response matches it.

Route 53 health checks and CloudWatch alarms send alerts to an SNS email subscription. You must confirm the subscription. These services, S3, and CloudFront can incur charges.

For temporary deployments, follow the [teardown and verification checklist](docs/operations.md#7-teardown-and-verify-one-environment) when finished. Destroying the website bucket permanently deletes all its object versions. Shared state and resources require a separate review.

## Security boundaries

- Files served through CloudFront are public. Do not put credentials or private data in `web`.
- S3 blocks public access; CloudFront is authorized with Origin Access Control.
- Infrastructure changes use an approved human or automation role. Website deployment uses a separate, restricted GitHub OIDC role.
- Production approval and branch protection must be configured in GitHub. The workflow also requires a successful GitHub staging deployment of the same commit before publishing to production.
- This configuration is a starting point, not proof of production readiness. Review the plan, policies, monitoring, costs, and account settings before applying it.
