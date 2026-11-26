# One Step At A Time

From curiosity to capable AI agents - one step at a time.

A single HTML page and a small Python API, both behind one CloudFront address. The page comes from a private S3 bucket. Version 2 adds the API: a FastAPI app in a Docker image, run by AWS Lambda. There is no database or AI model yet.

The API has two routes:

| Request | Reply (JSON) |
|---|---|
| `GET /api/health` | `{"status": "ok", "version": "<commit SHA>"}` |
| `GET /api/hello` | `{"message": "Welcome to the agentic world! This is One Step At A Time, where we build a RAG and agent app step by step."}` |

Anything else returns 404. There is no `/docs`, `/redoc` or `/openapi.json`, and `/api/hello` takes no parameters. The page has a button that calls `/api/hello` and shows the reply.

## Project structure

```text
one-step-towards-ai\
  app\
    main.py
    requirements.txt
  tests\
    test_main.py
  web\
    index.html
    app.js
  terraform\
    site\
      versions.tf
      main.tf
      api.tf
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
    staging-deployment-guide-v2.html
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
  Dockerfile
  .dockerignore
  requirements-dev.txt
  pyproject.toml
  .gitattributes
  .gitignore
  TODO.md
  README.md
```

- `app\main.py` is the whole API: FastAPI, with the welcome built from a LangChain prompt template (`langchain-core`, no AI model). `app\requirements.txt` pins `fastapi` 0.165.0, `uvicorn` 0.54.0 and `langchain-core` 1.8.5.
- `requirements-dev.txt` adds the test tools (`pytest` 9.2.0, `httpx2` 2.16.2). `pyproject.toml` holds pytest settings only.
- `Dockerfile` builds the API image. `.dockerignore` sends only `app\` to the build.
- `terraform\site\api.tf` holds the API resources: ECR repository, Lambda function, log group, execution role, function URL, CloudFront access control and invoke permissions.
- `docs\staging-deployment-guide-v2.html` is the illustrated guide for version 2.

Only `web/index.html` and `web/app.js` are published to S3. The `app` folder ships as a Docker image. The guides are in `docs`.

Commands below start from the repository root, the `one-step-towards-ai` folder. GitHub only runs workflows from `.github/workflows` at the repository root.

## Start here

1. Open the [illustrated deployment guide](docs/staging-deployment-guide.html) (HTML, with screenshots), then the [version 2 API guide](docs/staging-deployment-guide-v2.html).
2. Open `web\index.html` in a browser to preview the page. The button needs the API, so it works only on the deployed site.
3. Read the [operations guide](docs/operations.md) before provisioning AWS or setting up GitHub.
   For a manual staging setup, see the [step-by-step deployment guide](docs/staging-deployment.md).
4. Run the local checks, the same ones the `Checks` workflow runs on GitHub:

   ```powershell
   terraform fmt -check -recursive terraform
   & "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh
   ```

   `check-repo.sh` needs Git Bash. Plain `bash` in PowerShell usually starts WSL instead, so call Git Bash's `bash.exe` as shown, or run `bash scripts/check-repo.sh` inside a Git Bash window. It prints six `[OK]` lines and `All repository checks passed.`
5. Run the API tests and the API on your PC (next section).

The [operations guide](docs/operations.md) explains how to bootstrap a private state bucket with `scripts\bootstrap-state.ps1` before initializing the site backend. The script creates billable AWS resources only after confirmation; it does not deploy the site.

The Terraform AWS provider lock file is committed so different machines and CI use the same provider version. `terraform init -backend=false -lockfile=readonly` followed by `terraform validate` checks the infrastructure syntax without accessing AWS state.

## Run the API on your PC

The API needs Python 3.13. Create a virtual environment once, outside the repository, then activate it in each new PowerShell window:

```powershell
py -3.13 -m venv $env:USERPROFILE\venvs\one-step
& $env:USERPROFILE\venvs\one-step\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
```

Run the tests, then start the API:

```powershell
python -m pytest
uvicorn app.main:app
```

Open `http://127.0.0.1:8000/api/health` and `http://127.0.0.1:8000/api/hello`. Locally, `/api/health` reports the version `local`. Stop the server with Ctrl+C.

### Docker (optional)

Docker on your PC is optional: GitHub builds the image in the `Checks` and `Deploy website` workflows. With Docker Desktop running:

```powershell
docker build --build-arg APP_VERSION=local -t one-step-api .
docker run --rm -p 8001:8000 one-step-api
```

Then open `http://127.0.0.1:8001/api/health`. Port 8001 avoids a clash with `uvicorn` on 8000.

The image is `python:3.13-slim` and the AWS Lambda Web Adapter 1.1.0, both pinned by digest. It runs as the user `nobody`. The adapter checks `/api/health` before Lambda sends requests. The build argument `APP_VERSION` sets the version that `/api/health` reports; the workflows pass the commit SHA.

Behind an HTTPS-inspecting proxy such as Zscaler, `pip` in the build fails with `CERTIFICATE_VERIFY_FAILED`. Add a CA bundle that includes the proxy's root certificate:

```powershell
docker build --secret id=ca,src=<path-to-ca-bundle.pem> --build-arg APP_VERSION=local -t one-step-api .
```

The Dockerfile passes the bundle to `pip` only; it is not stored in the image.

## Architecture

```text
Browser -- HTTPS --> CloudFront --+-- /*     -- signed (OAC) --> private S3 bucket (index.html, app.js)
                                  +-- /api/* -- signed (OAC) --> Lambda function URL (us-east-2)
                                                                 Docker image from private ECR (us-east-2)
```

Staging and production have separate site buckets, CloudFront distributions, deployment roles, API functions, image repositories, and state keys. CloudFront caching is disabled. The deployment ships the API image first, then uploads `app.js` and `index.html` and checks that the public responses match them.

The API runs in `us-east-2` (Ohio) because the organization's region policy blocks Lambda in `us-east-1`. Lambda can pull images only from ECR in its own region, so the repository is there too. CloudFront is global, so the site keeps its address. The S3 bucket and monitoring stay in `us-east-1`.

Terraform creates the Lambda function once. After that, the `Deploy website` workflow ships new code: it pushes an image tagged with the commit SHA and points the function at it. Terraform ignores those image changes.

Route 53 health checks and CloudWatch alarms send alerts to an SNS email subscription. You must confirm the subscription. These services, S3, CloudFront, Lambda, ECR and CloudWatch Logs can incur charges.

For temporary deployments, follow the [teardown and verification checklist](docs/operations.md#7-teardown-and-verify-one-environment) when finished. Destroying the website bucket permanently deletes all its object versions. Shared state and resources require a separate review.

## Security boundaries

- Files served through CloudFront are public. Do not put credentials or private data in `web`.
- S3 blocks public access; CloudFront is authorized with Origin Access Control.
- The API is public through CloudFront, with no login. That is acceptable only while it serves fixed text; add protection before any AI call (step 3).
- The Lambda function URL uses `AWS_IAM` authorization, and only this CloudFront distribution may call it. Calling the function URL directly returns 403. The function's execution role may only write its own logs.
- Infrastructure changes use an approved human or automation role. Deployment uses a separate, restricted GitHub OIDC role: it may upload `index.html` and `app.js`, push images to the one ECR repository, and update the one Lambda function.
- The ECR repository URL contains the AWS account ID. Keep it in GitHub environment variables; never commit it.
- Production approval and branch protection must be configured in GitHub. The workflow also requires a successful GitHub staging deployment of the same commit before publishing to production.
- This configuration is a starting point, not proof of production readiness. Review the plan, policies, monitoring, costs, and account settings before applying it.
