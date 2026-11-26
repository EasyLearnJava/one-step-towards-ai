# Coding agent prompt: build a one-page AWS website with a Python API (runs on its own)

This prompt builds **version 2** of the project: the version 1 website plus a small Python API (FastAPI in a Docker image on AWS Lambda, behind the same CloudFront address) and a page button that calls it. The version 1 prompt, which builds only the static website, is in git tag `v1.0.0` (`git show v1.0.0:docs/coding-agent-prompt.md`).

## How to use this file (for the human)

1. Start a coding agent in an **empty folder** and paste everything between `PROMPT START` and `PROMPT END`. You do not give it any values and it asks you no questions: it chooses the project's names itself, then builds and checks the whole project on your PC.
2. The agent never contacts AWS or GitHub, never commits and never pushes. Its only downloads are the Terraform AWS provider, the pinned Python packages and, if Docker is installed, the two pinned base images. At the end it reports the names it chose, every check it ran with the result, and the values only you can supply.
3. **REPLACE BEFORE DEPLOYING.** The generated docs show your private values as tokens such as `<<AWS_ACCOUNT_ID>>`, `<<GITHUB_OWNER>>` and `<<ALERT_EMAIL>>`. They are **dynamic values that must be replaced with your own original values** when you deploy; the agent never guesses them. The "Values you need" table in the generated `docs/staging-deployment.md` says where to find each one.
4. To deploy: review the files, set your git identity, commit, push, then follow `docs/staging-deployment.md`.

---

<!-- PROMPT START -->

## 1. Goal

You are a senior cloud engineer working **on your own**. In the current folder, build a complete repository (version 2 of the project) that publishes **one HTML page** as a public HTTPS website on AWS, with a **small Python API** behind the same address:

- **Terraform**, run later by the operator from their PC, creates a private S3 bucket; a CloudFront distribution that reads it through Origin Access Control (OAC), adds five security headers and does not cache; a least-privilege IAM role that GitHub Actions assumes through OIDC (no stored AWS keys); a Route 53 HTTPS health check; a CloudWatch alarm; and an SNS email alert. For the API, in **us-east-2**: a private ECR image repository; an AWS Lambda function that runs the API's Docker image, with its log group, an execution role that may only write logs, and a private function URL (`AWS_IAM`); and a second OAC so that only this CloudFront distribution may call the function URL. CloudFront sends `/api/*` to the function and everything else to the bucket. 25 managed resources in total.
- **The API**: FastAPI with exactly two GET routes, `/api/health` (status and the commit SHA) and `/api/hello` (a fixed welcome built with a LangChain prompt template), no parameters and no documentation pages. One Docker image with the AWS Lambda Web Adapter runs it locally and on Lambda. The page gets a button whose script, `web/app.js`, calls `/api/hello` and shows the reply.
- **A separate S3 bucket for Terraform state**, created or checked by an idempotent PowerShell script.
- **GitHub Actions**: `Checks` runs on every pull request and every push to `main` (repository rules, Terraform format and validity, the API's tests, a build and smoke test of the Docker image, PowerShell parsing). `Deploy website` is started by hand; it builds and pushes the image, switches the Lambda function to it and verifies the live API, then uploads `app.js` and `index.html` and verifies the live page.
- **Two environments**, `staging` and `production`: the same code with different values, by default in one AWS account.
- **A repository check script** and **documentation** that a beginner can follow click by click to deploy.

There is no database, no load balancer and no AI model yet: the API is a walking skeleton that later steps extend.

**This run builds the repository and verifies it locally. Deploying is done later by the operator, using the docs you write.**

## 2. How you work: on your own, no questions

1. **Never ask the human anything and never wait for input.** Make every decision yourself. Where this prompt gives a default, use it. Where it leaves a choice open, choose the simplest option that keeps the security properties in section 5, and list it under "Decisions" in your final report with a one-line reason.
2. **Follow the reference exactly.** Section 7 gives the complete, tested content of every code and configuration file. Create each file with exactly that content, replacing only the five tokens from section 4.1. Do not add, remove or reword code, settings or comments. This includes changes you consider improvements, such as stricter error handling or extra comments: the reference was tested exactly as written. If you believe something in the reference is wrong, do not change it: describe it under "Suggested fixes" in your final report.
3. **Write the docs yourself** from section 8, copying each marked block word for word.
4. **Check your work** with section 10. If a check fails, fix your files and run it again, at most three times per check. If it still fails, leave the files as they are and report the exact error.
5. **Missing tools.** If `terraform`, `git`, `bash`, `powershell.exe`, Python 3.13 or Docker is not installed or not running, do everything else, mark the checks that need it **NOT RUN** with the reason, and give the exact command for the operator. Never report a check as passed unless you ran it and saw it pass.
6. Finish with the report in section 11.

## 3. Hard rules

1. **No cloud or remote actions in this run.** Do not run `aws`, `gh`, or any `terraform` command other than `fmt`, `validate`, `version` and `init -backend=false -lockfile=readonly`. Do not run `bootstrap-state.ps1`; only parse it. Do not run `git push`, `git remote add`, `git commit`, `git config user.*`, `docker login` or `docker push`. The only network access allowed is: `terraform init` downloading the AWS provider from the Terraform registry; `pip install -r requirements-dev.txt` into the git-ignored `.venv` folder, from PyPI; and `docker build` pulling the two base images pinned in the `Dockerfile`.
2. **Never invent private values.** The values in section 4.2 exist only in the operator's AWS and GitHub accounts. Never make them up, look them up, or take them from this computer (for example from `git config`, environment variables or AWS profiles). In the docs, write them exactly as the `<<NAME>>` tokens of section 4.2. Do not create `site.tfvars` or `backend.hcl`.
3. **No secrets.** Do not read `~/.aws/credentials`, `~/.aws/config`, `~/.aws/sso/cache`, environment variables such as `AWS_SECRET_ACCESS_KEY` or `AWS_SESSION_TOKEN`, or any token, password or key. The docs tell the operator never to store AWS keys in GitHub.
4. **Git.** Run `git init -b main` (or `git branch -M main` if the folder is already a repository). Leave every file uncommitted and unstaged: the commit author must be the operator's own GitHub identity, and this computer's global git identity may belong to someone else.
5. **Windows PowerShell 5.1** must run the `.ps1` script: no ternary `?:`, no `??`, no `ConvertFrom-Json -AsHashtable`, no `&&` or `||`. Save `.ps1` files as **plain ASCII**: no smart quotes or long dashes.
6. **Encoding and line endings.** Write every file as UTF-8 without a byte order mark, with LF line endings and a final newline. `scripts/check-repo.sh` must have LF endings or bash fails.
7. **Pinned versions.** Keep every pin exactly as given: the GitHub Action commit SHAs (including `actions/setup-python` v7.1.0), `terraform_version: 1.10.5`, `python-version: "3.13"`, the provider constraint `~> 5.0` and provider version 5.100.0 in the lock file, the Python packages (`fastapi==0.165.0`, `uvicorn==0.54.0`, `langchain-core==1.8.5`, `pytest==9.2.0`, `httpx2==2.16.2`), and the two base images in the `Dockerfile`, pinned by digest (`python:3.13-slim` and `aws-lambda-adapter:1.1.0`). Do not look up newer versions.
8. **Names.** Choose neutral names for a personal learning site. Do not use the name, brand or logo of a real company, product or person.

## 4. Values

### 4.1 Values you choose (filled into committed files)

Choose these five yourself, make them consistent with each other, and replace the tokens everywhere: in every file of section 7 and in the docs.

| Token | What it is | Rules | Example of the format |
|---|---|---|---|
| `<<PROJECT_SLUG>>` | Prefix of AWS resource names (including the ECR repository, Lambda function, log group and roles `<<PROJECT_SLUG>>-<env>-api`) and of the local Docker image name `<<PROJECT_SLUG>>-api` | Must match `^[a-z0-9][a-z0-9-]{1,8}[a-z0-9]$` (3 to 10 characters) and must not start with `xn--` or `sthree`. The state bucket `<<PROJECT_SLUG>>-v1-production-state-<32 hex>` is the slug length plus 53 characters and must stay within S3's limit of 63 | `cloudnotes` |
| `<<PROJECT_TAG>>` | `Project` tag on every resource, and the prefix of the state file key | lowercase letters, digits and hyphens; at most 40 characters | `cloud-learning-notes` |
| `<<SITE_TITLE>>` | The page `<title>` and `<h1>`, **and** the Route 53 health-check search string, **and** the app name in the API's welcome (`app/main.py`, `tests/test_main.py`) | Page text rule; at most 60 characters | `Cloud Learning Notes` |
| `<<SITE_EYEBROW>>` | Small line above the title | Page text rule; at most 60 characters | `Learning cloud deployment` |
| `<<SITE_TAGLINE>>` | Sentence under the title, the page description and the README's first line | Page text rule; at most 120 characters | `One page, delivered securely from AWS.` |

**Page text rule:** plain ASCII letters, digits, spaces and `. , : ! ? ' -` only. No `"`, `\`, `&`, `<`, `>`, `$`, `%`, `{` or `}`: these values go into Terraform strings, an HTML attribute, the health-check search string and Python strings (the title is also formatted by a LangChain prompt template), where such characters break the syntax or change the bytes the health check looks for. The title is case-sensitive and appears exactly the same in `web/index.html`, `main.tf`, `app/main.py` and `tests/test_main.py`.

**Other defaults:** use the region `us-east-1` for the site everywhere, and write it directly in the docs' commands with one note that another region means replacing `us-east-1` in the site commands (the alarm and SNS topic stay in `us-east-1` in every case). The API is fixed to **us-east-2** by `local.api_region` in `versions.tf`; the docs write `us-east-2` directly in the API commands and explain why (section 9). Both environments use one AWS workload account; the docs mention that a separate production account is possible and needs its own one-time setup.

### 4.2 Values only the operator has

Never invent these. The docs show each one exactly as its token, in the "Values you need" table (block A in section 8), so the operator can replace it before deploying.

## 5. Security properties that must hold

The reference code in section 7 already implements all of these. They are listed so you know what must never change and what the docs explain.

- **Website bucket:** Block Public Access on, ACLs disabled (BucketOwnerEnforced), versioning on, AES256 encryption. Its policy lets only this CloudFront distribution read objects (`AWS:SourceArn`) and denies every request that is not HTTPS.
- **CloudFront:** OAC signs every origin request (type `s3` for the bucket, type `lambda` for the function URL); HTTP redirects to HTTPS; only GET and HEAD; caching off (`Managed-CachingDisabled`) for the page and the API; `/api/*` goes to the function over HTTPS only (TLSv1.2) with `Managed-AllViewerExceptHostHeader` (the visitor's `Host` header is never forwarded); the same headers on page and API replies: `Content-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`, `Strict-Transport-Security: max-age=31536000`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`.
- **Deploy role:** trusted only for tokens from this repository's matching GitHub environment with audience `sts.amazonaws.com`; may only `s3:PutObject` on `index.html` and `app.js`; push images to this environment's one ECR repository (plus `ecr:GetAuthorizationToken`, which AWS does not allow to be limited to a repository); and `lambda:UpdateFunctionCode` and `lambda:GetFunctionConfiguration` on this environment's one function. It cannot list or read the bucket, delete images or change the function's settings.
- **API function:** the function URL uses `AWS_IAM`, so an unsigned call returns 403; two Lambda permissions, `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction`, are granted to `cloudfront.amazonaws.com` only for this distribution (`source_arn`); the execution role may only write to its own log group (14 days' retention); reserved concurrency 5 caps cost and abuse; the image runs as `nobody`; FastAPI's `/docs`, `/redoc` and `/openapi.json` are off; `/api/hello` sends `Cache-Control: no-store`.
- **Images:** private ECR repository with scan on push and AES256 encryption; a lifecycle rule keeps the newest 5 images; Lambda images are pushed as one plain image (`--provenance=false`) and the function is pinned to an image digest.
- **Page script:** `app.js` comes from the same address and shows the API's reply with `textContent`, never `innerHTML`.
- **Releases:** deploys run only from `main`; production deploys only a commit that already succeeded in staging, and that gate is the first step of the first job, before anything is built or pushed. `Checks` never contacts AWS.
- **State:** its own private, versioned, encrypted, HTTPS-only bucket with S3 native locking; never committed.
- **Monitoring:** health check every 30 seconds; alarm and SNS topic in `us-east-1`; missing data counts as unhealthy.

## 6. Repository layout

```text
.github/
  workflows/
    checks.yml
    deploy.yml
app/
  main.py
  requirements.txt
docs/
  operations.md
  staging-deployment.md
scripts/
  bootstrap-state.ps1
  check-repo.sh
terraform/
  site/
    .terraform.lock.hcl
    api.tf
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
tests/
  test_main.py
web/
  app.js
  index.html
.dockerignore
.gitattributes
.gitignore
Dockerfile
pyproject.toml
README.md
requirements-dev.txt
```

The repository root is this folder; GitHub only runs workflows from `.github/workflows` at the root. Git-ignored files the operator creates later (`site.tfvars`, `backend.hcl`, plans, state) and the local test environment (`.venv`, `.pytest_cache`, `__pycache__`) are not part of the layout.

## 7. Files (complete, tested reference)

Create every file below with exactly this content, replacing only `<<PROJECT_SLUG>>`, `<<PROJECT_TAG>>`, `<<SITE_TITLE>>`, `<<SITE_EYEBROW>>` and `<<SITE_TAGLINE>>`. No other `<<...>>` token appears in these files. The scripts were tested under Windows PowerShell 5.1 against fake AWS and Terraform commands covering every branch described below; the Terraform passed `terraform fmt -check` and `terraform validate`; the API's tests passed with the pinned packages; and the image built, ran as `nobody` and answered both routes, locally and on Lambda behind CloudFront.

### 7.1 `.gitignore`

```gitignore
# Terraform state, saved plans and the real per-environment settings
# (site.tfvars, backend.hcl) stay on the operator's PC. Only the example files
# and the provider lock file are committed. Python caches and the local
# virtual environment stay out too.
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
.pytest_cache/
.venv/
.DS_Store
```

### 7.2 `.gitattributes`

```gitattributes
# Shell scripts keep LF line endings on every checkout; bash fails on CRLF.
*.sh text eol=lf
```

### 7.3 `web/index.html`

Inline CSS and one script file from the same address, `app.js`: the Content Security Policy blocks inline scripts, images, fonts and anything from other sites. The title stays within the first 5,120 bytes for the health check. No header comment, because the page is public.

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
    button { margin-top: 1rem; padding: .8rem 1.6rem; border: 0; border-radius: .6rem; background: #1d4ed8; color: #fff; font: inherit; font-weight: 700; cursor: pointer; }
    button:hover { background: #1e40af; }
    button:disabled { opacity: .6; cursor: wait; }
    #reply { min-height: 3.2em; color: #172554; }
    #reply.error { color: #b91c1c; }
  </style>
  <script src="app.js" defer></script>
</head>
<body>
  <main>
    <span class="eyebrow"><<SITE_EYEBROW>></span>
    <h1><<SITE_TITLE>></h1>
    <p><<SITE_TAGLINE>></p>
    <button id="hello" type="button">Say hello to the API</button>
    <p id="reply" aria-live="polite"></p>
  </main>
</body>
</html>
```

### 7.4 `web/app.js`

```javascript
// Calls the API on the same address (CloudFront sends /api/* to Lambda) and
// shows the reply. textContent, never innerHTML: the reply is shown as text,
// so nothing in it can run as code.
document.addEventListener("DOMContentLoaded", () => {
  const button = document.getElementById("hello");
  const reply = document.getElementById("reply");

  button.addEventListener("click", async () => {
    button.disabled = true;
    reply.classList.remove("error");
    reply.textContent = "Asking the API...";
    try {
      const response = await fetch("/api/hello", { headers: { Accept: "application/json" } });
      if (!response.ok) {
        throw new Error(`The API answered ${response.status}.`);
      }
      const data = await response.json();
      reply.textContent = data.message;
    } catch (error) {
      reply.classList.add("error");
      reply.textContent = `Sorry, the API could not be reached. ${error.message}`;
    } finally {
      button.disabled = false;
    }
  });
});
```

### 7.5 Python packages and test settings

`app/requirements.txt` (the only packages in the image):

```text
# Packages the API needs at run time; the Docker image installs only these.
fastapi==0.165.0
uvicorn==0.54.0
langchain-core==1.8.5
```

`requirements-dev.txt` (local development and the `api` check). FastAPI's `TestClient` needs an HTTP client package; Starlette now expects `httpx2`, not `httpx`:

```text
# Local development and CI: the app's packages plus the test tools.
-r app/requirements.txt
pytest==9.2.0
# FastAPI's TestClient needs an HTTP client; Starlette now expects httpx2.
httpx2==2.16.2
```

`pyproject.toml` (pytest settings only; the app is not a package):

```toml
# Tool settings only; the app is not packaged or installed.
[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
```

### 7.6 `app/main.py`

Exactly two GET routes and nothing else. The welcome is fixed text built with a LangChain prompt template (no AI model yet); there is no name or any other parameter. FastAPI's documentation pages are turned off.

```python
"""<<SITE_TITLE>> API: two GET routes, /api/health and /api/hello.

Run locally: uvicorn app.main:app
"""

import os

from fastapi import FastAPI, Response
from langchain_core.prompts import PromptTemplate

WELCOME = PromptTemplate.from_template(
    "Welcome to the agentic world! This is {app_name}, where we build a RAG "
    "and agent app step by step."
)

# No /docs, /redoc or /openapi.json: only the two routes below exist.
app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)


@app.get("/api/health")
def health():
    # APP_VERSION is the commit SHA, set in the Docker image.
    return {"status": "ok", "version": os.environ.get("APP_VERSION") or "local"}


@app.get("/api/hello")
def hello(response: Response):
    response.headers["Cache-Control"] = "no-store"
    return {"message": WELCOME.format(app_name="<<SITE_TITLE>>")}
```

### 7.7 `tests/test_main.py`

Three tests: health, hello (exact text and header), and that nothing else is served.

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.json()["version"]


def test_hello():
    response = client.get("/api/hello")
    assert response.status_code == 200
    assert response.json() == {
        "message": "Welcome to the agentic world! This is <<SITE_TITLE>>, "
        "where we build a RAG and agent app step by step."
    }
    assert response.headers["cache-control"] == "no-store"


def test_nothing_else_is_served():
    for path in ["/docs", "/redoc", "/openapi.json", "/", "/api/other"]:
        assert client.get(path).status_code == 404
```

### 7.8 `Dockerfile` and `.dockerignore`

One image for every place the API runs. The AWS Lambda Web Adapter is copied in as a Lambda extension: on Lambda it turns each invocation into a normal HTTP request to uvicorn once `/api/health` answers, so the app has no Lambda-specific code (no Mangum). Both base images are pinned by digest. The optional `ca` build secret is only for building behind an HTTPS-inspecting proxy; GitHub builds do not use it.

`Dockerfile`:

```dockerfile
# <<SITE_TITLE>> API. The same image runs locally, on AWS Lambda (through
# the AWS Lambda Web Adapter) and, later, on ECS Fargate or EC2.
#
#   docker build --build-arg APP_VERSION=local -t <<PROJECT_SLUG>>-api .
#   docker run --rm -p 8000:8000 <<PROJECT_SLUG>>-api
#
# Behind an HTTPS-inspecting proxy, add a CA bundle that includes the proxy's
# root; it is used by pip only, never stored:
#   docker build --secret id=ca,src=<path to the CA bundle> ...

FROM python:3.13-slim@sha256:7249d5587b78209a006dc4a3b5340678f84ea729239193aa559962cd8c1fce50

# On Lambda the adapter turns each invocation into a normal HTTP request to
# uvicorn; outside Lambda it stays idle.
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0@sha256:17cfd08eff1dfea3f6a9a1e9c65fdac80aa4919b6085e746615530f43f57d2f1 /lambda-adapter /opt/extensions/lambda-adapter

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    AWS_LWA_READINESS_CHECK_PATH=/api/health

WORKDIR /srv
COPY app/requirements.txt app/requirements.txt
RUN --mount=type=secret,id=ca \
    if [ -f /run/secrets/ca ]; then export PIP_CERT=/run/secrets/ca; fi; \
    pip install --no-cache-dir -r app/requirements.txt
COPY app/ app/

# The commit SHA, reported by /api/health.
ARG APP_VERSION=local
ENV APP_VERSION=${APP_VERSION}

USER nobody
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`.dockerignore`:

```text
# Send only the app to the Docker build; tests, docs, Terraform and .git stay out.
*
!app/
app/__pycache__/
```

### 7.9 `terraform/site/versions.tf`

```hcl
# Terraform and AWS provider versions, the S3 state backend, and three AWS
# provider configurations: one for the site's region, one fixed to us-east-1
# for monitoring and one fixed to us-east-2 for the API.
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

# The API (ECR and Lambda) runs in us-east-2: the organization's region rule
# blocks Lambda in us-east-1, and Lambda pulls images only from ECR in its own
# region. CloudFront is global, so the site keeps its address.
locals {
  api_region = "us-east-2"
}

provider "aws" {
  alias  = "api"
  region = local.api_region

  default_tags {
    tags = {
      Project     = "<<PROJECT_TAG>>"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

### 7.10 `terraform/site/variables.tf`

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

### 7.11 `terraform/site/main.tf`

Exactly 15 managed resources and 6 data sources. The distribution and the `/api/*` route refer to the API resources in `api.tf` (section 7.12). The deploy policy names the function by a constructed ARN instead, so the deploy role can be created before the function.

```hcl
# One environment: a private S3 bucket served by CloudFront through Origin
# Access Control with security headers, the /api/* route to the API (api.tf),
# the GitHub Actions deploy role, and a health check whose alarm emails the
# operator. 15 managed resources here; api.tf adds 10.

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

# Five security headers on every response, page and API alike.
resource "aws_cloudfront_response_headers_policy" "site" {
  name = "<<PROJECT_SLUG>>-${var.environment}-security"

  security_headers_config {
    content_security_policy {
      # script-src and connect-src 'self': the page may run its own app.js and
      # call its own /api. Inline styles only; nothing from other sites.
      content_security_policy = "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
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

# Passes the visitor's query string and headers to the API, except Host: the
# function URL must receive its own host name, or Lambda rejects the request.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
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

  # The API's private function URL (api.tf), reached over HTTPS only with
  # signed requests. The URL looks like https://<id>.lambda-url.<region>.on.aws/
  origin {
    domain_name              = trimsuffix(trimprefix(aws_lambda_function_url.api.function_url, "https://"), "/")
    origin_id                = "api"
    origin_access_control_id = aws_cloudfront_origin_access_control.api.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # /api/* goes to the API; everything else falls through to the bucket
  # below. Never cached, same security headers as the page.
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "api"
    viewer_protocol_policy     = "redirect-to-https"
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.site.id
    compress                   = true
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

# Least privilege: the deploy role may only upload index.html and app.js, push
# images to this environment's ECR repository (api.tf), and switch the API
# function to a new image. It cannot list the bucket, read objects, delete the
# site or images, or change the function's settings.
data "aws_iam_policy_document" "deploy" {
  statement {
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.site.arn}/index.html",
      "${aws_s3_bucket.site.arn}/app.js",
    ]
  }

  # Point the function at the image just pushed, then read its state while
  # waiting for the update to finish. The ARN is built from the function's
  # name, not taken from the function, so this role can exist before the
  # function: in a new environment GitHub pushes the first image before the
  # function is created.
  statement {
    actions = [
      "lambda:GetFunctionConfiguration",
      "lambda:UpdateFunctionCode",
    ]
    resources = ["arn:aws:lambda:${local.api_region}:${data.aws_caller_identity.current.account_id}:function:<<PROJECT_SLUG>>-${var.environment}-api"]
  }

  # docker login to ECR. AWS does not allow this action to be limited to one
  # repository; the token alone grants nothing beyond the statement below.
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = [aws_ecr_repository.api.arn]
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

### 7.12 `terraform/site/api.tf`

Exactly 10 managed resources and 3 data sources, all in us-east-2 through the `aws.api` provider except the CloudFront OAC (CloudFront is global). The function is created from the newest image already in ECR, pinned by digest, and Terraform then ignores `image_uri`: the Deploy workflow ships new code. A brand-new environment therefore needs one image in ECR before the function can be created; the docs (section 8.2, "Rebuild procedure") give the order.

```hcl
# The API, version 2: a private ECR repository for its Docker images and a
# Lambda function that runs the newest image, with its log group, execution
# role, private function URL and the permissions that let only this CloudFront
# distribution call it. 10 managed resources, in us-east-2 (versions.tf): the
# organization's region rule blocks Lambda in us-east-1, and Lambda pulls
# images only from ECR in its own region.

# Private image repository. Every image is tagged with its commit SHA by the
# Deploy workflow and scanned when pushed. Disposable, like the website bucket:
# destroy also deletes every image in it.
resource "aws_ecr_repository" "api" {
  provider             = aws.api
  name                 = "<<PROJECT_SLUG>>-${var.environment}-api"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keeps only the newest 5 images; older ones are deleted about once a day.
resource "aws_ecr_lifecycle_policy" "api" {
  provider   = aws.api
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the newest 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# Starting image: the newest image in the repository, pinned by digest. It must
# exist before the function is created. After that the Deploy workflow ships
# new images and Terraform ignores the image (see lifecycle below).
data "aws_ecr_image" "api_start" {
  provider        = aws.api
  repository_name = aws_ecr_repository.api.name
  most_recent     = true
}

# Created before the function so Lambda does not create a log group that keeps
# logs forever.
resource "aws_cloudwatch_log_group" "api" {
  provider          = aws.api
  name              = "/aws/lambda/<<PROJECT_SLUG>>-${var.environment}-api"
  retention_in_days = 14
}

# Execution role: the function may only write its own logs.
data "aws_iam_policy_document" "api_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "<<PROJECT_SLUG>>-${var.environment}-api"
  assume_role_policy = data.aws_iam_policy_document.api_trust.json
}

data "aws_iam_policy_document" "api_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.api.arn}:*"]
  }
}

resource "aws_iam_role_policy" "api_logs" {
  name   = "write-logs"
  role   = aws_iam_role.api.id
  policy = data.aws_iam_policy_document.api_logs.json
}

# Runs the Docker image; the Lambda Web Adapter inside it passes each
# invocation to uvicorn once /api/health answers. Reserved concurrency 5 caps
# how many copies run at once, as a cost and abuse limit (the account's
# concurrency limit must be well above 5, or reserving fails).
resource "aws_lambda_function" "api" {
  provider      = aws.api
  function_name = "<<PROJECT_SLUG>>-${var.environment}-api"
  role          = aws_iam_role.api.arn
  package_type  = "Image"
  image_uri     = data.aws_ecr_image.api_start.image_uri
  architectures = ["x86_64"]
  memory_size   = 512
  timeout       = 15

  reserved_concurrent_executions = 5

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.api.name
  }

  depends_on = [aws_iam_role_policy.api_logs]

  lifecycle {
    # The Deploy workflow ships new code; Terraform must not roll the function
    # back to the starting image.
    ignore_changes = [image_uri]
  }
}

# Private HTTPS address for the function. AWS_IAM: every call must be signed by
# an identity allowed to invoke it, so a direct call returns 403. Only
# CloudFront is allowed (below).
resource "aws_lambda_function_url" "api" {
  provider           = aws.api
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "AWS_IAM"
}

# CloudFront signs every request it sends to the function URL (OAC of type
# lambda). POST requests (a later step) must also carry x-amz-content-sha256,
# the SHA-256 of the body.
resource "aws_cloudfront_origin_access_control" "api" {
  name                              = "<<PROJECT_SLUG>>-${var.environment}-api"
  description                       = "Signed access to the private API function URL."
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# AWS requires both actions for CloudFront to call a function URL:
# InvokeFunctionUrl and InvokeFunction. source_arn limits both to this one
# distribution; no other caller is allowed.
resource "aws_lambda_permission" "cloudfront_url" {
  provider               = aws.api
  statement_id           = "AllowCloudFrontServicePrincipal"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.api.function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.site.arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  provider      = aws.api
  statement_id  = "AllowCloudFrontServicePrincipalInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.site.arn
}
```

### 7.13 `terraform/site/outputs.tf`

```hcl
# After apply, website_url, site_bucket_name, deploy_role_arn,
# api_ecr_repository_url and api_function_name are copied into the GitHub
# environment variables WEBSITE_URL, SITE_BUCKET, AWS_ROLE_ARN,
# API_ECR_REPOSITORY and API_FUNCTION_NAME. The Deploy workflow reads the API's
# region from the repository URL.
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

output "api_ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "api_region" {
  value = local.api_region
}

output "api_function_name" {
  value = aws_lambda_function.api.function_name
}

# Private: calling it directly must return 403.
output "api_function_url" {
  value = aws_lambda_function_url.api.function_url
}
```

### 7.14 `terraform/site/.terraform.lock.hcl`

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

### 7.15 Environment example files

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

### 7.16 `.github/workflows/checks.yml`

Three jobs. `validate` (Ubuntu) runs the repository rules, then Terraform format, init without state and validate. `api` (Ubuntu) installs `requirements-dev.txt` with Python 3.13, runs the tests, builds the image (never pushed), starts it and checks that `/api/health` reports this commit and `/api/hello` the welcome. `scripts` (Windows) parses every `.ps1` file with Windows PowerShell 5.1. None of them touches AWS.

```yaml
# Runs on every pull request and every push to main. Checks the repository
# rules (scripts/check-repo.sh), Terraform formatting and validity, the API's
# tests and Docker image, and that the PowerShell scripts parse in Windows
# PowerShell 5.1. It never contacts AWS.
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

  api:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - uses: actions/setup-python@6d4fd22b20465ccc0f7354476588e8df7c9ca0e0 # v7.1.0
        with:
          python-version: "3.13"
      - name: Install packages
        run: python -m pip install -r requirements-dev.txt
      - name: Run tests
        run: python -m pytest
      - name: Build the Docker image (not pushed)
        run: docker build --build-arg "APP_VERSION=${GITHUB_SHA}" -t <<PROJECT_SLUG>>-api .
      - name: Start the image and call the API
        run: |
          docker run -d --name api -p 8000:8000 <<PROJECT_SLUG>>-api
          for i in $(seq 1 30); do
            curl -fsS http://127.0.0.1:8000/api/health > health.json && break
            sleep 1
          done
          cat health.json; echo
          grep -q "\"version\":\"${GITHUB_SHA}\"" health.json
          curl -fsS http://127.0.0.1:8000/api/hello | grep -q "Welcome to the agentic world"
          echo "Image answers /api/health with this commit and /api/hello with the welcome."
      - name: Container logs
        if: always()
        run: docker logs api || true

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

### 7.17 `.github/workflows/deploy.yml`

Two jobs, both only from `main` and in the chosen GitHub environment. `api` runs first: the production gate (its first step, so nothing is built or pushed for production before it passes), then it builds the image with `--provenance=false` (one plain image; the default build pushes an image index with an attestation, which Lambda rejects), tags it with the commit SHA, pushes it, pins the function to the image digest that ECR reports, waits for the update, and checks that the live `/api/health` reports this commit. `deploy` runs after it and uploads `app.js` before `index.html`, so a new page never loads an old script. The run option "image only" stops after the push; it is for an environment whose function does not exist yet.

```yaml
# Manual release, in two jobs that use the OIDC deploy role (no stored AWS
# keys). api builds the API's Docker image, pushes it to the environment's ECR
# repository, switches the Lambda function to it and checks that the live API
# reports this commit. deploy then uploads app.js and index.html and checks that
# the live files match byte for byte. Production first requires a successful
# staging deployment of the same commit.
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
      image_only:
        description: "Only build and push the API image to ECR (skip the API update and the page)"
        required: false
        type: boolean
        default: false

permissions:
  contents: read
  deployments: read
  id-token: write

concurrency:
  group: website-${{ inputs.environment }}
  cancel-in-progress: false

jobs:
  # The API: build the image on Linux, tag it with the commit SHA, push it to
  # the environment's ECR repository, switch the Lambda function to it and
  # check the live API reports this commit. "Image only" stops after the push.
  api:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    env:
      API_ECR_REPOSITORY: ${{ vars.API_ECR_REPOSITORY }}
      API_FUNCTION_NAME: ${{ vars.API_FUNCTION_NAME }}
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
      - name: Read registry and region from the repository URL
        run: |
          set -euo pipefail
          # <account>.dkr.ecr.<region>.amazonaws.com/<name>
          registry="${API_ECR_REPOSITORY%%/*}"
          echo "API_REGISTRY=${registry}" >> "$GITHUB_ENV"
          echo "API_REGION=$(echo "$registry" | cut -d. -f4)" >> "$GITHUB_ENV"
      - name: Configure AWS credentials with OIDC
        uses: aws-actions/configure-aws-credentials@7474bc4690e29a8392af63c5b98e7449536d5c3a # v4.3.1
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.API_REGION }}
      - name: Log in to ECR
        run: aws ecr get-login-password --region "$API_REGION" | docker login --username AWS --password-stdin "$API_REGISTRY"
      - name: Build and push the image
        run: |
          set -euo pipefail
          # --provenance=false: push one plain image. By default the build adds
          # an attestation and pushes an image index, which Lambda rejects.
          docker build --provenance=false --build-arg "APP_VERSION=${GITHUB_SHA}" -t "${API_ECR_REPOSITORY}:${GITHUB_SHA}" .
          docker push "${API_ECR_REPOSITORY}:${GITHUB_SHA}"
      - name: Verify the image is in ECR
        run: |
          set -euo pipefail
          digest="$(aws ecr batch-get-image --region "$API_REGION" \
            --repository-name "${API_ECR_REPOSITORY#*/}" \
            --image-ids "imageTag=${GITHUB_SHA}" \
            --query 'images[0].imageId.imageDigest' --output text)"
          case "$digest" in
            sha256:*) ;;
            *) echo "Image ${GITHUB_SHA} not found in ECR." >&2; exit 1 ;;
          esac
          # repository@sha256:...; the function is pinned to this exact image.
          echo "API_IMAGE=${API_ECR_REPOSITORY}@${digest}" >> "$GITHUB_ENV"
          echo "Image ${GITHUB_SHA} is in ECR: ${digest}"
      - name: Switch the Lambda function to this image
        if: ${{ !inputs.image_only }}
        run: |
          set -euo pipefail
          aws lambda update-function-code --region "$API_REGION" \
            --function-name "$API_FUNCTION_NAME" --image-uri "$API_IMAGE" > /dev/null
          # Waits until the update has finished (or failed).
          aws lambda wait function-updated --region "$API_REGION" --function-name "$API_FUNCTION_NAME"
          echo "Function ${API_FUNCTION_NAME} now runs ${API_IMAGE}"
      - name: Verify the live API runs this commit
        if: ${{ !inputs.image_only }}
        run: |
          set -euo pipefail
          for attempt in $(seq 1 12); do
            if curl --fail --silent --show-error --max-time 15 "${WEBSITE_URL}/api/health" -o /tmp/health.json \
               && grep -q "\"version\":\"${GITHUB_SHA}\"" /tmp/health.json; then
              curl --fail --silent --show-error --max-time 15 "${WEBSITE_URL}/api/hello" | grep -q "Welcome to the agentic world"
              echo "Verified API ${GITHUB_SHA} at ${WEBSITE_URL}/api"
              exit 0
            fi
            echo "API not yet on this commit; retry ${attempt}/12."
            sleep 10
          done
          echo "API verification failed." >&2
          exit 1

  # The page: index.html and app.js, after the API is live.
  deploy:
    needs: api
    if: github.ref == 'refs/heads/main' && !inputs.image_only
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    env:
      AWS_REGION: ${{ vars.AWS_REGION }}
      SITE_BUCKET: ${{ vars.SITE_BUCKET }}
      WEBSITE_URL: ${{ vars.WEBSITE_URL }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
      - name: Configure AWS credentials with OIDC
        uses: aws-actions/configure-aws-credentials@7474bc4690e29a8392af63c5b98e7449536d5c3a # v4.3.1
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}
      - name: Publish the page
        run: |
          set -euo pipefail
          # app.js first, so the new page never loads an old script.
          aws s3api put-object \
            --bucket "$SITE_BUCKET" \
            --key app.js \
            --body web/app.js \
            --content-type 'text/javascript; charset=utf-8' \
            --cache-control 'no-cache' \
            --metadata "commit=${GITHUB_SHA}" > /dev/null
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
               && cmp -s web/index.html /tmp/deployed-index.html \
               && curl --fail --silent --show-error --max-time 15 "${WEBSITE_URL}/app.js" -o /tmp/deployed-app.js \
               && cmp -s web/app.js /tmp/deployed-app.js; then
              echo "Verified release ${GITHUB_SHA} at ${WEBSITE_URL}"
              exit 0
            fi
            echo "Page not yet verified; retry ${attempt}/12."
            sleep 10
          done
          echo "Deployment verification failed." >&2
          exit 1
```

### 7.18 `scripts/bootstrap-state.ps1`

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

### 7.19 `scripts/check-repo.sh`

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

Write plain, friendly Markdown for a beginner. Use the five values you chose, `us-east-1` for the site and `us-east-2` for the API directly; write every section 4.2 value as its token. Copy blocks A to G **word for word** (they sit between `BLOCK ... START` and `BLOCK ... END` lines; copy what is between the lines, not the marker lines), replacing only the five section 4.1 tokens inside them. Never paraphrase an error message, a console path, an action list or an expected output.

### 8.1 `README.md`

1. `# <<SITE_TITLE>>`, then `<<SITE_TAGLINE>>` on its own line.
2. "What this is": one HTML page published over HTTPS from a private S3 bucket through CloudFront, plus a small Python API behind the same address: `GET /api/health` returns `{"status": "ok", "version": "<commit SHA>"}` and `GET /api/hello` returns a fixed welcome; the page's button calls `/api/hello`. No database, load balancer or AI model yet.
3. Architecture as a text block:

   ```text
   Browser --HTTPS--> CloudFront --+-- /*     --signed (OAC)--> private S3 bucket (index.html, app.js)
                                   +-- /api/* --signed (OAC)--> Lambda function URL (us-east-2)
                                                                Docker image from ECR: Python 3.13,
                                                                FastAPI + LangChain, Lambda Web Adapter
   Route 53 health check --> CloudWatch alarm (us-east-1) --> SNS email
   GitHub Actions --OIDC, no stored keys--> deploy role: upload index.html and app.js,
                                            push API images, switch the function's image
   Terraform state --> its own private S3 bucket
   ```

4. The layout from section 6, one line per file saying what it is for.
5. "Checks": what `Checks` runs (repository rules, Terraform format and validity, the API's tests, a build and smoke test of the Docker image, script parsing in Windows PowerShell 5.1), and a link to "Running the checks locally" in `docs/operations.md`. Do not list the check commands in the README.
6. "Run the API on your PC": with Python 3.13, `uvicorn app.main:app --reload` after installing `requirements-dev.txt` into `.venv`, then open `http://127.0.0.1:8000/api/health`; or the two `docker` commands from the top of the `Dockerfile`.
7. "Security boundaries": everything in `web/` is public; no credentials in the repository; Terraform runs with the operator's own AWS identity while deploys use the restricted OIDC role; the function URL is private and only this CloudFront distribution may call it; production needs GitHub approval and a commit that passed staging; never commit `site.tfvars`, `backend.hcl`, state or plans.
8. "Why us-east-2 for the API": the reference organization's region rule blocks Lambda in us-east-1; Lambda can pull images only from ECR in its own region, so ECR is there too; CloudFront is global, so the site keeps its address.
9. "Cost": about $2 to $6 per month per environment, mostly the Route 53 health check's HTTPS and text-matching features; the API adds a few cents at low traffic (ECR storage for at most 5 images, Lambda requests and logs); check current AWS prices.
10. "Start here": link `docs/staging-deployment.md` (first deployment) and `docs/operations.md` (production, operations, teardown).

### 8.2 `docs/staging-deployment.md` (click-by-click first deployment)

Sections in this order:

1. **What you will build**: the page with its button, the URL form `https://<random>.cloudfront.net`, the API at `/api/health` and `/api/hello` on the same address, the cost line from the README, and that every step that changes AWS or GitHub is done by you.
2. **Values you need**: block A.
3. **One-time setup (check before you redo it)**: block B, then block C.
4. **Create the state bucket**: from the repository root in a PowerShell window, `.\scripts\bootstrap-state.ps1 -Environment staging -Region us-east-1 -ExpectedAccountId "<<AWS_ACCOUNT_ID>>" -WhatIf`, then the same command without `-WhatIf`, answering `Y`. Show the expected output from block D. Say that if `backend.hcl` already exists the script only checks the bucket, and that the operator can also copy `backend.example.hcl` to `backend.hcl` for an existing approved bucket and then run the script with `-WhatIf` to check it.
5. **Configure staging, then create the image repository and the deploy role** (the first part of the rebuild procedure): `Copy-Item .\terraform\environments\staging\site.example.tfvars .\terraform\environments\staging\site.tfvars` (only if it does not exist), fill in every value from block A, then:

   ```powershell
   Set-Location .\terraform\site
   terraform init -reconfigure "-backend-config=..\environments\staging\backend.hcl"
   terraform plan "-var-file=..\environments\staging\site.tfvars" "-target=aws_ecr_lifecycle_policy.api" "-target=aws_iam_role_policy.deploy" "-out=staging-first.tfplan"
   terraform apply staging-first.tfplan
   aws ecr describe-repositories --region us-east-2 --repository-names <<PROJECT_SLUG>>-staging-api --query "repositories[0].repositoryUri" --output text
   aws iam get-role --role-name <<PROJECT_SLUG>>-staging-github-deploy --query "Role.Arn" --output text
   Set-Location ..\..
   ```

   Call steps 5 to 8 the **rebuild procedure** (the operations guide refers to it) and explain why it is needed: the Lambda function starts from the newest image in its ECR repository and a new repository is empty, and the CloudFront distribution depends on the function, so a plain first apply fails; the deploy role does not depend on the function (its policy builds the function's ARN from the name), so it can be created first. This targeted plan creates 5 resources: the website bucket, the ECR repository, its keep-5 rule, the deploy role and its policy. Terraform's warning that resource targeting is in effect is expected for this step only. The two `aws` commands only read: they print the repository URL and the role ARN that GitHub needs next, because `terraform output` may not list them after a targeted apply. Say that every new or rebuilt environment (also production, and staging after a teardown) uses this procedure. Show the expected output from block D.
6. **Publish with GitHub and push the first image**: set the repo-local identity (`git config --local user.name "<<GIT_AUTHOR_NAME>>"`, `git config --local user.email "<<GIT_AUTHOR_EMAIL>>"`), stage files by path (never `git add -A`), commit, `git remote add origin https://github.com/<<GITHUB_OWNER>>/<<GITHUB_REPO>>.git`, `git push -u origin main`; wait for a green `Checks` run (three jobs: `validate`, `api`, `scripts`); create the `staging` environment with two of its variables for now, `AWS_ROLE_ARN` and `API_ECR_REPOSITORY`, from step 5; run **Actions > Deploy website > Run workflow**, branch `main`, environment `staging`, with **image only** ticked. GitHub builds the image with `--provenance=false`, pushes it tagged with the commit SHA, checks it is in ECR and stops; no Docker is needed on your PC.
7. **Create the rest of staging**:

   ```powershell
   Set-Location .\terraform\site
   terraform plan "-var-file=..\environments\staging\site.tfvars" "-out=staging.tfplan"
   terraform apply staging.tfplan
   terraform output
   ```

   Explain each command in one line and show the expected output from block D (20 to add, 25 resources in total). Say that a saved plan can be applied only once, that CloudFront takes several minutes, that 403 for the page and an alarm are normal until the first full deploy, and that `/api/health` already answers with the commit of the image-only run once the distribution is deployed.
8. **Finish GitHub and deploy**: add the other four variables so the environment has all six (block A); run **Actions > Deploy website > Run workflow**, branch `main`, environment `staging`, **image only** not ticked; confirm the SNS email ("AWS Notification - Subscription Confirmation", "Confirm subscription").
9. **Check the deployment**: block F.
10. **Troubleshooting**: block E.

### 8.3 `docs/operations.md`

1. **Prerequisites**: a short summary that links to block B in the staging guide.
2. **Staging**: the commands from the staging guide, without the explanations.
3. **Production**: create the `production` environment (branch rule `main`, required reviewers where the plan allows) **before** the first production run; its variables are added during the rebuild procedure (two before the image-only run, all six before the full run); run the bootstrap with `-Environment production`; create `production\site.tfvars` with `<<SITE_BUCKET_NAME_PRODUCTION>>`; `terraform init -reconfigure` with the production backend; then the rebuild procedure from the staging guide with `production` names: the targeted plan and apply (check in the plan that the deploy role's trust `sub` ends in `:environment:production`), `AWS_ROLE_ARN` and `API_ECR_REPOSITORY` on the `production` environment, a **new** staging run on the current `main` commit followed by a production Deploy run of the same commit with **image only** ticked, the full plan and apply, and the other four variables; finally a **new** production run of the same commit without image only (never "Re-run jobs" on an old run). The production gate is the first step of the `api` job, so nothing is built or pushed for production before it passes.
4. **Operate and recover**: roll back by reverting in Git and deploying again through staging and production (each run ships the API and the page of that commit together); the health check needs `<<SITE_TITLE>>` in the page and in `main.tf` (change both together); caching is off and access logging is not enabled; the API's logs are in CloudWatch Logs (us-east-2), log group `/aws/lambda/<<PROJECT_SLUG>>-<env>-api`, kept 14 days; ECR keeps the newest 5 images and shows each image's scan findings; Terraform ignores the function's image, so code changes ship only through Deploy website; a rebuilt environment goes through the rebuild procedure again (targeted apply, image-only run, full apply), and afterwards `WEBSITE_URL` and `SITE_BUCKET` must be updated and the new SNS email confirmed; review costs and budget alerts.
5. **Teardown of one environment**: pause deployments first (Actions > Deploy website > "..." > Disable workflow); from `terraform/site`, `terraform init -reconfigure` with that environment's backend, and `terraform state list` shows the 25 resources (lines starting with `data.` are data sources, not resources); do not delete ECR images by hand first, because planning reads the newest image; `terraform plan -destroy "-var-file=..\environments\staging\site.tfvars" "-out=staging-destroy.tfplan"`; review; `terraform apply staging-destroy.tfplan`, which ends with `Apply complete! Resources: 0 added, 0 changed, 25 destroyed.`; `terraform state list` then prints nothing (Terraform waits for AWS to confirm each deletion and keeps any failed one in the state); the state bucket, OIDC provider, budgets and SCP entries are separate decisions. Destroying the website bucket deletes every version of the page, and destroying the ECR repository deletes every image in it.
6. **Running the checks locally**: block G.

### 8.4 Blocks to copy word for word

<!-- BLOCK A START: Values you need -->
Replace every token below with your own real value. **Never commit these values**: they go only into the git-ignored `site.tfvars` and `backend.hcl`, command arguments, your local git settings and GitHub settings.

| Token | What it is | Where to find it | Where it goes |
|---|---|---|---|
| `<<AWS_ACCOUNT_ID>>` | The 12-digit AWS account that will host the site | AWS console, account menu at the top right; or `aws sts get-caller-identity` | `-ExpectedAccountId` of the bootstrap script; the ECR registry address when you push the first image |
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

After `terraform apply`, set these six **environment variables** (not repository variables) in GitHub > Settings > Environments > `staging` (and later `production`):

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` (the site's region) |
| `SITE_BUCKET` | `terraform output -raw site_bucket_name` |
| `WEBSITE_URL` | `terraform output -raw website_url` (no trailing slash) |
| `AWS_ROLE_ARN` | `terraform output -raw deploy_role_arn` |
| `API_ECR_REPOSITORY` | `terraform output -raw api_ecr_repository_url` (the Deploy workflow reads the API's region, us-east-2, from it) |
| `API_FUNCTION_NAME` | `terraform output -raw api_function_name` |
<!-- BLOCK A END -->

<!-- BLOCK B START: One-time setup -->
Each step is needed once per account or repository. Check first; skip it if it is already done.

| Step | Where | Why you do it yourself | How to check it is already done |
|---|---|---|---|
| AWS account with a payment method, budget alerts and MFA on the root user | AWS console | Card details and account security are yours alone | Billing and Cost Management > Payment preferences shows a card; Budgets lists a budget |
| AWS CLI **version 2**, signed in to the account that will host the site | Your PC | Your keys or SSO sign-in are private. The scripts use `--no-cli-pager`, which version 1 rejects | `aws --version` shows `aws-cli/2.`; `aws sts get-caller-identity` shows `<<AWS_ACCOUNT_ID>>` |
| Your signed-in AWS identity may manage S3 buckets and policies, CloudFront distributions, origin access controls and response headers policies, IAM roles and inline policies (including passing the API's role to Lambda), Route 53 health checks, SNS topics and subscriptions, CloudWatch alarms, ECR repositories, lifecycle policies, repository policies and image pushes, Lambda functions, function URLs, permissions and concurrency, and CloudWatch Logs log groups; for teardown also list and delete S3 object versions | IAM or IAM Identity Center | This is your infrastructure identity, not the GitHub deploy role | `terraform plan` and `terraform apply` run without `AccessDenied` |
| Terraform 1.10 or later (below 2.0), Git, and Git Bash for `scripts/check-repo.sh` | Your PC | Installation | `terraform version`; `git --version`; `Test-Path "$env:ProgramFiles\Git\bin\bash.exe"` prints `True` |
| Docker Desktop, running (optional) | Your PC | Only to build and test the image on your PC; GitHub builds and pushes every image that is deployed | `docker version` shows a Server section |
| Python 3.13 (only to run the API's tests on your PC) | Your PC | Installation | `py -3.13 --version` prints `Python 3.13.` |
| Lambda concurrency in us-east-2 is well above 5 | Service Quotas (region us-east-2) > AWS Lambda > Concurrent executions | The function reserves 5; new accounts can start at 10, which leaves nothing to reserve | `aws lambda get-account-settings --region us-east-2 --query "AccountLimit.ConcurrentExecutions"` prints a number such as `1000`; if it prints `10`, request an increase and wait for it before the full apply |
| PowerShell may run local scripts | Your PC | Windows blocks scripts by default on many PCs | `Get-ExecutionPolicy` shows `RemoteSigned`, `Unrestricted` or `Bypass`. Otherwise run `Set-ExecutionPolicy -Scope Process Bypass` in that window only |
| GitHub sign-in provider for AWS (one per account, shared by projects) | IAM > Identity providers > Add provider > OpenID Connect. Provider URL `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com` | Account-wide setting | `token.actions.githubusercontent.com` is listed with audience `sts.amazonaws.com` |
| CloudFront account verification, **only if** apply fails with "Your account must be verified before you can add new CloudFront resources" | Support Center > Create case > Account and billing > Account Activation > Account Verification | Only AWS Support can lift it | The case shows Resolved |
| Organization region policy, **only if** a command fails with "explicit deny in a service control policy" | See "If AWS says explicit deny in a service control policy" below | Only the management account can change it | The policy's exceptions include every action in the list below |
| An empty GitHub repository (no README, license or .gitignore) with default branch `main` | github.com > New repository | Ownership and visibility are your choice | The repository page loads; Settings > General shows default branch `main` |
| A GitHub plan that supports environments for this repository | Repository visibility or your GitHub plan | Environments exist on every plan for **public** repositories. **Private** repositories need GitHub Pro or Team (or Enterprise) for environments, and Enterprise for required reviewers. The deploy role trusts only environment tokens, so without environments nothing can deploy | Settings shows an "Environments" entry |
| Protect `main`: pull request review and the required checks `validate` and `scripts` (recommended) | Settings > Rules > Rulesets (or Settings > Branches) | Repository policy | The rule lists `main` and both checks |
| Environment `staging`, and later `production` | Settings > Environments > New environment; Deployment branches and tags > Selected branches and tags > add `main` | Repository settings | The environment exists with the `main` rule; production also has required reviewers where your plan allows. **Create `production` before any production run**: starting a run for a missing environment makes GitHub create it with no protection and no variables |
| The six environment variables (Values you need) | Settings > Environments > `<env>` > Environment variables | They come from your Terraform outputs | All six are present on the environment |
| Confirm the alert email | The `<<ALERT_EMAIL>>` inbox: "AWS Notification - Subscription Confirmation" > Confirm subscription | Only the mailbox owner can confirm; the link expires after 3 days | SNS (region us-east-1) > Topics > `<<PROJECT_SLUG>>-<env>-alerts` > Subscriptions shows Confirmed |
| Run the deploy | Actions > Deploy website > Run workflow > branch `main` > environment ("image only" not ticked) | Releases are deliberate | A green run with two green jobs, `api` and `deploy` |
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

The API is in **us-east-2** on purpose: the reference organization's region policy blocks Lambda in us-east-1 and allows us-east-2, so Lambda, ECR and the API's logs need no exception. If your policy also restricts us-east-2, your administrators must allow `ecr:*`, `lambda:*` and `logs:*` there.
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

**Targeted `terraform plan`** (rebuild procedure, first part) for a new environment ends with:

```text
Plan: 5 to add, 0 to change, 0 to destroy.
```

and `terraform apply staging-first.tfplan` ends with `Apply complete! Resources: 5 added, 0 changed, 0 destroyed.` Both print a warning that resource targeting is in effect; that is expected for this step only. The two `aws` commands then print:

```text
<<AWS_ACCOUNT_ID>>.dkr.ecr.us-east-2.amazonaws.com/<<PROJECT_SLUG>>-staging-api
arn:aws:iam::<<AWS_ACCOUNT_ID>>:role/<<PROJECT_SLUG>>-staging-github-deploy
```

**Deploy website with image only**: the `api` job's step "Verify the image is in ECR" prints

```text
Image <commit SHA> is in ECR: sha256:<64 hex characters>
```

the next two steps are skipped, and the `deploy` job is skipped.

**Full `terraform plan`** after the image-only run ends with:

```text
Plan: 20 to add, 0 to change, 0 to destroy.
```

**`terraform apply staging.tfplan`** takes several minutes (CloudFront is the slowest) and ends with:

```text
Apply complete! Resources: 20 added, 0 changed, 0 destroyed.

Outputs:

api_ecr_repository_url = "<<AWS_ACCOUNT_ID>>.dkr.ecr.us-east-2.amazonaws.com/<<PROJECT_SLUG>>-staging-api"
api_function_name = "<<PROJECT_SLUG>>-staging-api"
api_function_url = "https://<id>.lambda-url.us-east-2.on.aws/"
api_region = "us-east-2"
aws_account_id = "<<AWS_ACCOUNT_ID>>"
deploy_role_arn = "arn:aws:iam::<<AWS_ACCOUNT_ID>>:role/<<PROJECT_SLUG>>-staging-github-deploy"
site_bucket_name = "<<SITE_BUCKET_NAME_STAGING>>"
website_url = "https://<random>.cloudfront.net"
```

The environment then has 25 resources.

**Deploy website** run: the last step of the `api` job prints

```text
Verified API <commit SHA> at https://<random>.cloudfront.net/api
```

and the last step of the `deploy` job prints

```text
Verified release <commit SHA> at https://<random>.cloudfront.net
```

**Teardown**: `terraform apply staging-destroy.tfplan` ends with `Apply complete! Resources: 0 added, 0 changed, 25 destroyed.`, and `terraform state list` then prints nothing.

**`scripts/check-repo.sh`** (run with Git Bash, see "Running the checks locally" in `docs/operations.md`) prints six `[OK]` lines and `All repository checks passed.`

**`python -m pytest`** ends with `3 passed`.
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
| 7 | "Verify the live API runs this commit" or "Verify the public page matches this release" fails after about 2 minutes | `WEBSITE_URL` still points at an old CloudFront address; every destroy and new apply creates a new one | Update `WEBSITE_URL` (and `SITE_BUCKET` if it changed) and confirm the new SNS email |
| 8 | Creating the website bucket fails right after a destroy | The old bucket name is still being released | Wait a few minutes and plan again, or choose a new name and update `SITE_BUCKET` |
| 9 | "Saved plan is stale", or apply refuses a plan | A saved plan can be applied only once | Run `terraform plan ... -out=...` again |
| 10 | Production fails: "No successful staging deployment found for <SHA>." | Production needs the same commit to have succeeded in staging; "Re-run jobs" reuses an old commit | Start a new staging run on the current `main` commit, then a new production run |
| 11 | A script stops at the first AWS warning or error line after you edited it | Windows PowerShell 5.1 turns `2>&1` output into a terminating error under `$ErrorActionPreference = "Stop"` | Keep the `Invoke-AwsRaw` pattern: local `Continue`, then check `$LASTEXITCODE` |
| 12 | `git commit -m "... \"quoted\" ..."` in PowerShell turns words into file paths | PowerShell 5.1 splits native arguments at inner double quotes | Write the message to a file and use `git commit -F <file>` |
| 13 | GitHub shows an unexpected contributor | The commit email belongs to another GitHub account, for example a global work identity | Set `git config --local user.name` and `user.email` before the first commit; rewriting pushed history needs a force-push, so decide that carefully |
| 14 | `Checks` fails at `terraform init -lockfile=readonly` | The lock file is missing or selects a different provider version | Commit `terraform/site/.terraform.lock.hcl` unchanged |
| 15 | The health check fails although the page loads | The page title and `search_string` in `main.tf` differ, or the title moved beyond the first 5,120 bytes | Keep them identical and near the top; `scripts/check-repo.sh` checks this |
| 16 | Images, fonts, inline scripts or anything from another site do not load | The Content Security Policy allows only inline styles, scripts from this address (`app.js`) and calls to this address (`/api`) | Widen the policy in `main.tf` deliberately, for example `img-src 'self'` |
| 17 | Visitors see an old page | Only possible if caching is turned on (it is off by design) | Keep caching off, or add a CloudFront invalidation step and `cloudfront:CreateInvalidation` for the deploy role |
| 18 | The bootstrap creates a second state bucket | `backend.hcl` was deleted, so the script assumed a first-time setup | Never delete `backend.hcl` while the environment exists; it is git-ignored on purpose |
| 19 | The bootstrap's real run fails with "Windows PowerShell is in NonInteractive mode. Read and Prompt functionality is not available." | It asks for confirmation, and the shell cannot answer (for example an agent or a scheduled task) | Run it yourself in a PowerShell window and answer `Y`, or add `-Confirm:$false` there |
| 20 | Adding `-Confirm:$false` fails with "Cannot convert 'System.String' to the type 'System.Management.Automation.SwitchParameter' required by parameter 'Confirm'." | The script was started with `powershell -File`, which passes `$false` as text | Type the command in a PowerShell window instead |
| 21 | `Checks` never runs on push, and Deploy website is skipped | The branch is not called `main` | `git branch -M main`, push `main`, and make it the default branch |
| 22 | GitHub has no Environments settings, or deploys from a private repository cannot assume the role | Your GitHub plan has no environments for private repositories | Make the repository public, or use a plan that supports them |
| 23 | A production run has no reviewers, or fails because its variables are empty | `production` was started before the environment existed, so GitHub created it bare | Create `production` with its branch rule and reviewers before any production run; set `AWS_ROLE_ARN` and `API_ECR_REPOSITORY` before the image-only run and all six variables before the full run |
| 24 | `curl -I <url>` in Windows PowerShell errors or prints an object | `curl` is an alias of `Invoke-WebRequest` there | Use `curl.exe` |
| 25 | A script that worked fails to parse after an edit | A smart quote or long dash was saved in a UTF-8 file without a byte order mark | Keep `.ps1` files plain ASCII; `scripts/check-repo.sh` and the `scripts` check catch this |
| 26 | `Checks` fails at "Check repository rules" | A `[FAIL]` line names the problem: page title and health check differ, an unfilled token, an account ID or GitHub ID pair in a file, a non-ASCII character in a script, or a local-only file not ignored | Fix what the `[FAIL]` line names, then push again |
| 27 | `bash scripts/check-repo.sh` typed in PowerShell starts WSL, fails with Linux errors, or says `bash` is not recognized | In PowerShell, `bash` is usually WSL's `C:\Windows\System32\bash.exe` or nothing at all: Git Bash's `bash.exe` is in `C:\Program Files\Git\bin`, which is usually not on PATH | Run it in Git Bash, or in PowerShell with `& "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh` |
| 28 | The `.terraform` folder in `terraform\site` is about 630 MB | `terraform init` unpacks the AWS provider there | It is git-ignored and safe to delete; the next `terraform init` downloads it again |
| 29 | `check-repo.sh` stops after a `grep:` or `fatal:` line, without "All repository checks passed." or "Repository checks failed." | A search could not run, for example "grep: scripts/*.ps1: No such file or directory" when the `scripts` folder holds no `.ps1` files. The script stops rather than report a check it could not run as passed | Fix what the error line names, then run it again |
| 30 | Applying a new environment without the targeted step stops with an error from `data.aws_ecr_image.api_start` | The function starts from the newest image in ECR, and the repository is still empty | Follow the rebuild procedure in the staging guide: run Deploy website with **image only** ticked (the deploy role and repository may already exist), then plan and apply again |
| 31 | Creating the function, or "Switch the Lambda function to this image", fails because the image's media type or manifest is not supported | The image was pushed as an image index with an attestation, which `docker build` does by default | Build with `--provenance=false` and push again; the Deploy workflow already does this |
| 32 | Creating the function fails on `ReservedConcurrentExecutions` and the account's minimum unreserved concurrency | The account's Lambda concurrency in us-east-2 is too low to reserve 5 (new accounts can start at 10) | Request a higher "Concurrent executions" quota in Service Quotas (us-east-2), then plan and apply again |
| 33 | `/api/health` through CloudFront returns 403, and the button shows "Sorry, the API could not be reached. The API answered 403." | CloudFront's calls are not accepted: one of the two Lambda permissions is missing, the API's OAC is not of type `lambda`, or the visitor's `Host` header is forwarded | Keep `api.tf` and the `Managed-AllViewerExceptHostHeader` origin request policy exactly as given, and apply again. Calling the function URL directly returning 403 is correct |
| 34 | The Deploy `api` job fails at "Configure AWS credentials with OIDC" or "Log in to ECR" with a missing or invalid region | `API_ECR_REPOSITORY` is missing or wrong; the workflow reads the API's region from it | Set it to `terraform output -raw api_ecr_repository_url` on that environment |
| 35 | The image-only run fails at "Configure AWS credentials with OIDC" in a new environment | `AWS_ROLE_ARN` or `API_ECR_REPOSITORY` is not set yet, or the targeted apply did not include `aws_iam_role_policy.deploy` | Set both from the two `aws` commands in the rebuild procedure, and run the targeted plan and apply exactly as given |
| 36 | The `api` check fails while pulling from `public.ecr.aws` with a 429 error | The public registry limits anonymous pulls of the Lambda Web Adapter image | Re-run the failed job a little later |
| 37 | `docker build` on your PC fails in `pip install` with certificate errors | An HTTPS-inspecting proxy re-signs the downloads | Build with `--secret id=ca,src=<path to a CA bundle that includes the proxy's root>` as shown at the top of the `Dockerfile`; the bundle is used by pip only and is not stored in the image |
| 38 | The button does nothing | `app.js` was not uploaded, or the CSP lost `script-src 'self'` | Run Deploy website (it uploads `app.js` before `index.html`) and keep the CSP in `main.tf` as given |
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

# The API through CloudFront: status ok and the deployed commit SHA, then the welcome
curl.exe -sS "$url/api/health"
curl.exe -sS "$url/api/hello"

# Only the two routes exist: prints 404 (the API's own answer)
curl.exe -sS -o NUL -w '%{http_code}' "$url/api/nope"

# The function URL itself is private: prints 403
curl.exe -sS -o NUL -w '%{http_code}' (terraform output -raw api_function_url)

# The alarm reads "OK" (allow up to about 5 minutes after the first deploy)
aws cloudwatch describe-alarms --region us-east-1 --alarm-names <<PROJECT_SLUG>>-staging-unavailable --query "MetricAlarms[0].StateValue"

# The email subscription prints an ARN, not "PendingConfirmation"
aws sns list-subscriptions-by-topic --region us-east-1 --topic-arn "arn:aws:sns:us-east-1:<<AWS_ACCOUNT_ID>>:<<PROJECT_SLUG>>-staging-alerts" --query "Subscriptions[0].SubscriptionArn"

# The page's commit matches the deployed commit
aws s3api head-object --bucket $bucket --key index.html --query "Metadata.commit"

# The function's image is pinned by digest: the URI ends in @sha256:<digest>
aws lambda get-function --region us-east-2 --function-name <<PROJECT_SLUG>>-staging-api --query "Code.ImageUri"
```

In the `curl.exe -I` output, look for `content-security-policy` (with `script-src 'self'; connect-src 'self'`), `strict-transport-security: max-age=31536000`, `x-content-type-options: nosniff`, `x-frame-options: DENY`, `referrer-policy: no-referrer`, `cache-control: no-cache` and `x-cache: Miss from cloudfront`. `/api/health` prints `{"status":"ok","version":"<commit SHA>"}`. In the browser, the button shows the welcome and the developer console shows no Content Security Policy errors. The Deploy website run has already compared the live `index.html` and `app.js` with `web/` byte for byte.
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

**API tests (PowerShell, from the repository root, Python 3.13).** The `.venv` folder is git-ignored; create it once:

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe -m pytest
```

The tests end with `3 passed`. To try the API by hand, run `.\.venv\Scripts\python.exe -m uvicorn app.main:app --reload` and open `http://127.0.0.1:8000/api/health` and `http://127.0.0.1:8000/api/hello`; stop it with Ctrl+C.

**Docker image (PowerShell, from the repository root, Docker Desktop running).** The same build and smoke test as the `api` check, without pushing anything:

```powershell
docker build --build-arg APP_VERSION=local -t <<PROJECT_SLUG>>-api .
docker run --rm -d --name <<PROJECT_SLUG>>-api -p 8000:8000 <<PROJECT_SLUG>>-api
curl.exe -sS http://127.0.0.1:8000/api/health
curl.exe -sS http://127.0.0.1:8000/api/hello
docker stop <<PROJECT_SLUG>>-api
```

`/api/health` prints `{"status":"ok","version":"local"}` (wait a few seconds after `docker run` if the first call fails).

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

Version 2 (the API):

- **Lambda in us-east-2**, through the `aws.api` provider and `local.api_region`: the reference organization's region rule blocks Lambda in us-east-1, and Lambda pulls images only from ECR in its own region, so ECR is there too. CloudFront is global, so the site keeps its address. The site, state bucket, alarm and SNS topic stay in us-east-1.
- **A Docker image with the AWS Lambda Web Adapter, not a zip and not Mangum**: the app is a plain FastAPI app started by `uvicorn`, the same image runs locally, on Lambda now and on ECS Fargate or EC2 later, and images may be far larger than zip packages, which later LangChain and RAG libraries need. GitHub builds the image on Linux, so compiled packages match Lambda.
- **`docker build --provenance=false`** wherever an image is pushed: by default the build adds an attestation and pushes an image index, which Lambda rejects.
- **One address, private function**: CloudFront sends `/api/*` to a Lambda function URL with `AWS_IAM` auth, signed by an OAC of type `lambda`. AWS requires **both** `lambda:InvokeFunctionUrl` and `lambda:InvokeFunction` for this, each limited to this distribution with `source_arn`. No CORS is needed because the page and the API share one origin. POST requests in a later step must send `x-amz-content-sha256`.
- **`Managed-AllViewerExceptHostHeader`** on `/api/*`: forwarding the visitor's `Host` header makes Lambda reject the request; the function URL must receive its own host name.
- **`ignore_changes = [image_uri]`** with the starting image from `data.aws_ecr_image` (`most_recent`, pinned by digest): code ships through the Deploy workflow like the page, with the same staging-then-production gate; Terraform must never roll the function back. The price is that a new environment needs one image in ECR before the function can be created, hence the rebuild procedure: a targeted apply of the ECR repository and the deploy role, a Deploy run with "image only", then the full apply.
- **The deploy policy builds the function's ARN from its name** (`local.api_region`, the account ID and `<<PROJECT_SLUG>>-<env>-api`) instead of referring to the function, so the deploy role exists before the function and GitHub can push the first image. Keep the name in the ARN identical to `function_name` in `api.tf`.
- **Reserved concurrency 5**: a cost and abuse cap until later steps add protection.
- **ECR `force_delete = true` and a keep-5 lifecycle rule**: a teardown removes the images with the repository, and storage stays at a few cents.
- **Deploy role least privilege**: `s3:PutObject` only on `index.html` and `app.js`; ECR push actions only on this environment's repository plus `ecr:GetAuthorizationToken` (AWS cannot scope it; the token alone grants nothing more); `lambda:UpdateFunctionCode` and `lambda:GetFunctionConfiguration` only on this function. No ECR repository policy is managed: Lambda adds its own image-retrieval statement when the function is created.
- **The production gate is the first step of the `api` job**, so nothing is built, pushed or switched for production before the staging check passes. The `deploy` job needs `api`, and uploads `app.js` before `index.html`.
- **CSP `script-src 'self'; connect-src 'self'`** is the smallest widening that lets the page run its own `app.js` and call its own `/api`; `app.js` writes the reply with `textContent`, never `innerHTML`, so nothing in a reply can run as code.
- **FastAPI's `/docs`, `/redoc` and `/openapi.json` are off** and the test proves nothing else is served. `/api/hello` takes no parameters (a name parameter was considered and dropped to keep the API to two plain GET routes).
- **`httpx2`** in `requirements-dev.txt`: FastAPI's `TestClient` needs an HTTP client, and Starlette now expects `httpx2`.
- **`Checks` never contacts AWS**: the `api` job builds and smoke-tests the image locally on the runner and never pushes it.
- **Pins**: actions by commit SHA, Python packages by exact version, base images by digest, so a rebuild produces the tested image.

## 10. Verify locally (no AWS, no GitHub)

Run these and keep each result for the report:

1. Run `scripts/check-repo.sh` with Git Bash: `bash scripts/check-repo.sh` in a Git Bash shell, or `& "$env:ProgramFiles\Git\bin\bash.exe" scripts/check-repo.sh` from PowerShell (never plain `bash` in PowerShell, which is usually WSL). It prints six `[OK]` lines and `All repository checks passed.`
2. `terraform fmt -check -recursive terraform` prints nothing and exits 0.
3. In `terraform/site`: `terraform init -backend=false -lockfile=readonly` (it puts the AWS provider in the git-ignored `terraform/site/.terraform` folder, about 630 MB on disk; leave it there; the warning "Provider lock file not updated" is harmless), then `terraform validate`, which prints `Success! The configuration is valid.` Afterwards `.terraform.lock.hcl` must be unchanged.
4. In Windows PowerShell 5.1 (`powershell.exe`), from the repository root, run the script-syntax block from block G (the `scripts` job in `checks.yml` runs the same parser); it prints `All scripts parse in Windows PowerShell 5.1...`. Without `powershell.exe`, run it with `pwsh` and report "parsed with PowerShell 7 only", or mark it NOT RUN.
5. Both workflow files are valid YAML, for example `python -c "import sys, yaml; [yaml.safe_load(open(f, encoding='utf-8')) for f in sys.argv[1:]]" .github/workflows/checks.yml .github/workflows/deploy.yml`. Without Python and PyYAML, mark it NOT RUN.
6. **API tests:** with Python 3.13, run the "API tests" commands from block G (a `.venv` in the repository root, `pip install -r requirements-dev.txt`, `python -m pytest`); the output ends with `3 passed`. Without Python 3.13, mark it NOT RUN.
7. **Docker image:** if Docker is installed and running, run the "Docker image" commands from block G; `/api/health` prints `{"status":"ok","version":"local"}` and `/api/hello` prints the welcome with your `<<SITE_TITLE>>`. Stop the container afterwards. Never log in to a registry or push. Without Docker, or if pulling the base images fails (for example behind an HTTPS-inspecting proxy), mark it NOT RUN with the error.
8. **Fidelity:** compare every file you created from section 7 with its reference after replacing the five tokens. Any other difference is a failure: fix it. A difference you made on purpose is still a failure: restore the reference and describe your idea under "Suggested fixes".
9. **Counts:** `terraform/site/main.tf` and `api.tf` together hold exactly 25 `resource` blocks (15 and 10) and 9 `data` blocks (6 and 3), for example `git grep --untracked -c -E "^resource " -- terraform/site` and `git grep --untracked -c -E "^data " -- terraform/site`, which print `main.tf` and `api.tf` with those numbers.
10. **Docs:** blocks A to G appear word for word; no section 4.1 token is left anywhere (`git grep --untracked -n -E "<<(PROJECT_SLUG|PROJECT_TAG|SITE_TITLE|SITE_EYEBROW|SITE_TAGLINE)>>"` prints nothing); every section 4.2 token used in the docs is in block A.
11. `git status --short` lists only the files of section 6 as untracked (`??`), nothing is staged, and `git branch --show-current` prints `main`. The git-ignored `.venv`, `.pytest_cache`, `__pycache__` and `terraform/site/.terraform` folders do not appear.

## 11. Final report

End your run with this report, and nothing after it:

1. **Decisions**: the five values you chose and why, and any other choice you made.
2. **Files created**: the list.
3. **Checks**: for each check in section 10, the command, PASS, FAIL or NOT RUN, and the key output line.
4. **Suggested fixes**: anything in the reference you believe is wrong, with the reason (or "none").
5. **Before you deploy**: every section 4.2 token the operator must replace, pointing to the "Values you need" table, and these next steps: review the files; `git config --local user.name` and `user.email`; stage by path and commit; create the GitHub repository; add the remote and push; follow `docs/staging-deployment.md`.

<!-- PROMPT END -->
