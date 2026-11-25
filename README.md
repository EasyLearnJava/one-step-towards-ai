# One Step At A Time

From curiosity to capable AI agents - one step at a time.

A single HTML page, designed to be delivered through CloudFront from a private S3 bucket. There is no application server, Docker image, database, or AI service in this first release.

## Project structure

```text
v1-static-site\
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
    step-01-static-website.pdf
    operations.md
  scripts\
    bootstrap-state.ps1
    check-site-resources.ps1
  .github\
    workflows\
      checks.yml
      deploy.yml
  .gitignore
  README.md
```

Only `web/index.html` is published. The V1 learning guide is stored as a PDF in `docs`.

Commands below start from the `v1-static-site` folder. GitHub only discovers workflows at the repository root in `.github/workflows`. If this folder is kept inside a larger repository, its workflows must be relocated and adapted to the repository paths before they can run; alternatively, use this folder as its own repository.

## Start here

1. Review the [V0 prerequisites PDF](../v0-prerequisites/docs/aws-and-terraform-prerequisites.pdf), if V0 is available alongside V1.
2. Open the [V1 static website guide](docs/step-01-static-website.pdf).
3. Open `web\index.html` in a browser to preview the page.
4. Read the [operations guide](docs/operations.md) before provisioning AWS or setting up GitHub.
   For a manual staging setup, see the [step-by-step deployment guide](docs/staging-deployment.md).
5. Run the local infrastructure checks:

   ```powershell
   terraform fmt -check -recursive terraform
   ```

The [operations guide](docs/operations.md) explains how to bootstrap a private state bucket with `scripts\bootstrap-state.ps1` before initializing the site backend. The script creates billable AWS resources only after confirmation; it does not deploy the site.

The Terraform AWS provider lock file is committed so different machines and CI use the same provider version. `terraform init -backend=false -lockfile=readonly` followed by `terraform validate` checks the infrastructure syntax without accessing AWS state.

## Architecture

```text
Browser -- HTTPS --> CloudFront -- signed origin request --> private S3 bucket
```

Staging and production have separate site buckets, CloudFront distributions, deployment roles, and state keys. CloudFront caching is disabled initially; the deployment uploads only `index.html` and checks that the public response matches it.

Route 53 health checks and CloudWatch alarms send alerts to an SNS email subscription. You must confirm the subscription. These services, S3, and CloudFront can incur charges.

For temporary deployments, capture the resource inventory after applying Terraform and follow the [teardown and verification checklist](docs/operations.md#7-teardown-and-verify-one-environment) when finished. Destroying the website bucket permanently deletes all its object versions. Shared state and resources require a separate review.

## Security boundaries

- Files served through CloudFront are public. Do not put credentials or private data in `web`.
- S3 blocks public access; CloudFront is authorized with Origin Access Control.
- Infrastructure changes use an approved human or automation role. Website deployment uses a separate, restricted GitHub OIDC role.
- Production approval and branch protection must be configured in GitHub. The workflow also requires a successful GitHub staging deployment of the same commit before publishing to production.
- This configuration is a starting point, not proof of production readiness. Review the plan, policies, monitoring, costs, and account settings before applying it.
