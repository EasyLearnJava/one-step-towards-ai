# TODO: step 2, a Python API that welcomes you to the agentic world

Step 2 is a walking skeleton: the smallest version of the future RAG and
agent app that runs end to end on the real stack (Python, FastAPI,
LangChain, Docker, AWS Lambda, CloudFront, CI/CD), with no AI model yet.
Later steps add capabilities to this skeleton instead of rebuilding it.

## What it does

| Request | Reply (JSON) |
|---|---|
| `GET /api/hello` | `{"message": "Welcome to the agentic world! This is One Step At A Time, where we build a RAG and agent app step by step."}` |
| `GET /api/health` | `{"status": "ok", "version": "<commit SHA>"}` |

Only these two GET routes exist; no parameters, no `/docs`. The page gets a
button that calls `/api/hello`.

```text
Browser --HTTPS--> CloudFront --+-- /*          --> private S3 bucket (index.html, app.js)
                                +-- /api/*      --signed (OAC)--> Lambda function URL
                                                   Docker image from ECR (us-east-2):
                                                   Python 3.13, FastAPI + LangChain,
                                                   AWS Lambda Web Adapter
```

## Decided

- [x] Compute: AWS Lambda in us-east-2 (not EC2 or ECS Fargate for now).
- [x] Packaging: a Docker image on Lambda, with the AWS Lambda Web Adapter,
      stored in a private ECR repository. The same image can later run on
      ECS Fargate or EC2 unchanged.
- [x] Welcome wording above is final. No name parameter (dropped
      2026-11-26 to keep the API to two plain GET routes).
- [x] LangChain from step 2: the welcome is built with a LangChain prompt
      template (pinned `langchain-core`).
- [x] Code is shipped by the GitHub Deploy workflow, not by Terraform.
- [x] Reserved concurrency of 5 on the staging function, as a cost and abuse
      cap (the us-east-2 account limit is 400, so this is allowed).

## Design choices (and why)

1. **FastAPI, not a bare Lambda handler**: routes will grow (`/api/ask`,
   `/api/chat`, `/api/ingest`); validation and a local dev server. The image
   just runs `uvicorn app.main:app`; on Lambda the Lambda Web Adapter turns
   each Lambda call into a normal web request, so no Lambda-specific code is
   needed (no Mangum).
2. **LangChain from day one, no AI model**: proves LangChain packages build,
   deploy and import on Lambda and measures the cold start, at zero AI cost.
3. **Lambda in us-east-2**: the organization's region policy blocks Lambda in
   us-east-1 and allows everything in us-east-2 (Bedrock included).
   CloudFront is global, so the site keeps its address.
4. **One address, private function**: CloudFront sends `/api/*` to a Lambda
   function URL that only CloudFront may call (Origin Access Control). No
   CORS. Known limit for step 3: POST requests through OAC need the page to
   send a SHA-256 hash of the body (`x-amz-content-sha256`).
5. **Code ships through the Deploy workflow**: app code is a release like the
   page, so it follows the same staging-then-production gate. GitHub builds
   the image on Linux, so compiled packages such as `pydantic-core` match
   Lambda. Terraform creates the function and ignores later image updates.
6. **Docker image from day one**: Lambda images can be up to 10 GB (zips
   only 250 MB unpacked), so LangChain and RAG libraries fit; the same image
   runs locally, on Lambda now and on Fargate or EC2 later; the Lambda Web
   Adapter already supports response streaming for step 3.
7. **No load balancer**: CloudFront is the single HTTPS address and routes
   `/*` to S3 and `/api/*` to Lambda; Lambda gives every request its own copy
   of the function (up to the concurrency limit), so there is nothing to
   balance; Route 53 and the deploy workflow do the health checks. A load
   balancer (ALB) is needed only for always-on servers or containers, and
   bills every hour even with no traffic.

## Step 2, piece by piece

Each piece is small, ends with a check you can see, and leaves everything
working. Pieces 2.0 to 2.5 happen only on your PC and GitHub. From 2.6 on,
pieces change AWS: you run Terraform yourself, as in the guide. Suggested
commit after each piece (commits happen only when you say so).

### 2.0 Get ready (no code)

- [x] Confirm the open decisions (done 2026-11-26, see Decided).
- [x] Check the Lambda concurrency limit:
      `aws lambda get-account-settings --region us-east-2`. If it is 10, do
      not reserve concurrency. Result: 400, so 2.8 reserves 5.
- [x] Create the venv (Python 3.13, outside the repository). Created with
      Python 3.13.5:

```powershell
py -3.13 -m venv $env:USERPROFILE\venvs\one-step
& $env:USERPROFILE\venvs\one-step\Scripts\Activate.ps1
python --version
```

**Done when:** the decisions are confirmed and `python --version` prints 3.13.

### 2.1 Health endpoint, on your PC

- [x] `app/main.py`: FastAPI app with `GET /api/health`; the version is the
      commit SHA from the `APP_VERSION` environment variable, `local` when
      not set. FastAPI's `/docs`, `/redoc` and `/openapi.json` are off.
- [x] `app/requirements.txt` (pinned fastapi, uvicorn) and
      `requirements-dev.txt` (pytest, httpx2: Starlette deprecated httpx
      for its test client).
- [x] `tests/test_main.py`: health returns 200 with a status and version.
- [x] `pyproject.toml`: pytest settings only (tests folder, import path).

**Done when:** `python -m pytest` passes, and with
`uvicorn app.main:app --reload` running,
http://127.0.0.1:8000/api/health shows `"status": "ok"`.

### 2.2 Hello

- [x] `GET /api/hello` in `app/main.py` returns the welcome, built with a
      LangChain prompt template (pinned `langchain-core` 1.8.5), with
      `Cache-Control: no-store`.
- [x] Tests: the route's reply and header, and that nothing else is served.

**Done when:** tests pass and http://127.0.0.1:8000/api/hello shows the
welcome.

### 2.3 Hello with a name (dropped)

Dropped on 2026-11-26: `/api/hello` takes no parameters, so there is no name
check, no 422 and no name logging.

### 2.4 Docker image

- [x] `Dockerfile`: pinned Python 3.13 base image (by digest), requirements,
      app, the AWS Lambda Web Adapter (1.1.0, by digest), a non-root user;
      runs `uvicorn app.main:app` on the port the adapter is told to use;
      adapter readiness check on `/api/health`; commit SHA passed in as a
      build argument.
- [x] `.dockerignore`: only `app/` is sent to the build.
- [x] Local builds pass through Zscaler, which re-signs HTTPS: build with
      `--secret id=ca,src=$env:USERPROFILE\certs\zscaler-ca-bundle.pem`
      (public CAs plus the Zscaler root; used by pip only, not stored in
      the image). GitHub builds need no secret.

Checked on 2026-11-26: image 281 MB, Python 3.13.18, runs as `nobody`;
`/api/health` and `/api/hello` answer, `/docs` is 404.

**Done when:** the image builds (on your PC with Docker Desktop, or on
GitHub in 2.5), and if run locally with
`docker run --rm -p 8000:8000 one-step-api`, `/api/health` answers.

### 2.5 Checks on GitHub

- [x] `.github/workflows/checks.yml`: new `api` job with Python 3.13 that
      installs the requirements and runs `python -m pytest`, and a Docker
      build of the image (no push); actions pinned by commit SHA
      (setup-python v7.1.0). It also starts the image and checks
      `/api/health` reports the commit SHA and `/api/hello` the welcome.
- [x] `scripts/check-repo.sh` still passes on the new files.
- [ ] Open a pull request from `step-2` (Checks runs on pull requests and on
      pushes to `main` only) and see every job green.

**Done when:** after you push, every Checks job is green.

### 2.6 AWS part 1: region and image registry (you run Terraform)

- [ ] Terraform: second AWS provider for us-east-2; private ECR repository
      (scan on push, lifecycle rule keeping the last few images); output
      the repository URL.
- [ ] Deploy role: may push images to this repository only.
- [ ] GitHub variable `API_ECR_REPOSITORY` on `staging`.
- [ ] The staging stack was destroyed, so this apply also rebuilds the
      existing 15 resources: update `SITE_BUCKET` and `WEBSITE_URL`, confirm
      the new SNS email, run the deploy once for the page.

**Done when:** the apply succeeds, the empty repository appears in ECR
(us-east-2), and the page is live again.

### 2.7 First image in ECR

- [ ] Deploy workflow: new job that builds the image on Linux, tags it with
      the commit SHA and pushes it to ECR. A run option ("image only") stops
      after the push, because the function does not exist yet.

**Done when:** ECR lists an image tagged with the commit SHA.

### 2.8 AWS part 2: the Lambda function (you run Terraform)

- [ ] Terraform: execution role (logs only), log group (14 days), Lambda
      function from the image (`package_type = "Image"`, `ignore_changes` on
      the image), reserved concurrency 5, function URL (`AWS_IAM`).
- [ ] Outputs: function name and region; GitHub variables
      `API_FUNCTION_NAME` and `API_REGION` on `staging`.

**Done when:** the function shows as Active in the Lambda console
(us-east-2), and calling the function URL directly returns 403.

### 2.9 AWS part 3: the CloudFront route (you run Terraform)

- [ ] Terraform: Lambda-type Origin Access Control, CloudFront's invoke
      permission(s) as current AWS docs require, and the `/api/*` behavior
      (caching disabled, query string forwarded, Host header not forwarded,
      same security headers).

**Done when:** these return the expected JSON through CloudFront, and the
function URL called directly still returns 403:

```powershell
curl.exe -sS "https://<your-cloudfront-domain>/api/health"
curl.exe -sS "https://<your-cloudfront-domain>/api/hello"
```

### 2.10 Deploy the API from GitHub

- [ ] Deploy role: `lambda:UpdateFunctionCode` and
      `lambda:GetFunctionConfiguration` on this function only (Terraform).
- [ ] Deploy workflow: after pushing the image, update the function to it,
      wait for the update, verify `/api/health` reports this commit and
      `/api/hello` returns the welcome; then the page as before.

**Done when:** a Deploy run is green and `/api/health` shows that run's
commit.

### 2.11 Page part 1: allow the script (you run Terraform)

- [ ] Terraform: CSP adds `script-src 'self'; connect-src 'self'`; deploy
      role may also upload `app.js`.

**Done when:** `curl.exe -sS -I` on the site shows the new
`content-security-policy`, and the page looks unchanged.

### 2.12 Page part 2: button

- [ ] `web/index.html`: button and result line; the title stays
      "One Step At A Time" (the health check looks for it).
- [ ] `web/app.js`: calls `/api/hello` and shows the reply with
      `textContent`, never `innerHTML`.
- [ ] Deploy workflow: uploads and verifies `app.js` with `index.html`.

**Done when:** after a deploy, the button shows the welcome, the browser
console shows no CSP errors, and the health-check alarm
stays OK.

### 2.13 Docs

- [ ] README: architecture, layout, local checks, Docker.
- [ ] `docs/staging-deployment.md`, `docs/operations.md` and the HTML guide:
      new stage for the API (ECR, the first-time order of 2.6 to 2.9, the
      Docker image), why us-east-2, how to test, troubleshooting, costs.
- [ ] Teardown: delete the ECR images before the repository can be destroyed
      (or mark the repository as force-delete).
- [ ] Resource counts: 15 becomes the new total everywhere.

**Done when:** `scripts/check-repo.sh` passes and every link works.

### 2.14 Coding-agent prompt

- [ ] Update `docs/coding-agent-prompt.md` so it builds this version (the v1
      prompt stays in tag `v1.0.0`), and re-run its checks.

**Done when:** the prompt rebuilds and its checks pass.

### 2.15 Release

- [ ] Commit, push, wait for Checks, tag `v2.0.0`.
- [ ] Production is not built yet; promoting to production stays in step 6.

**Done when:** Checks is green on the tagged commit and `v2.0.0` is on
GitHub.

## Later steps (toward RAG and agents)

- **Step 3, first AI answer**: `POST /api/ask` calls Claude, with answers
  streamed. Before any AI call is public, add protection (login or rate
  limit) and a budget alarm.
- **Step 4, RAG**: documents in S3, embeddings, a vector store (for example
  Amazon S3 Vectors or Qdrant), answers with citations, scored with RAGAS.
- **Step 5, agent**: a LangGraph agent with tools (retriever first),
  conversation memory (for example DynamoDB), tracing.
- **Step 6, production hardening**: login, firewall, alarms, production
  promotion.
- **If Lambda is outgrown** (jobs over 15 minutes, always-running workers,
  local models): move the same image to ECS Fargate. A load balancer (ALB)
  comes in then, with CloudFront in front of it; expect roughly $16 or more
  a month for it even with no traffic (check current ALB pricing).

### AI model path

Claude through AWS IAM, so no API key exists anywhere (the Lambda role gets
permission):

| | Amazon Bedrock | Claude Platform on AWS |
|---|---|---|
| Run by | AWS | Anthropic |
| Billing | AWS bill | AWS Marketplace |
| Model ID | `anthropic.claude-opus-5-5` | `claude-opus-5-5` |
| Features | Core: messages, streaming, tool use, caching, citations | Everything Anthropic's own API has, including web search and Managed Agents |

Default model: Claude Opus 5.5 (cheaper Claude models exist if cost matters
more). Decide between the two in step 3, after checking which LangChain
supports better.

### Keep in mind: Bedrock pricing tiers

The tiers are the same models sold at different service levels; only some of
them make calls cheaper.

| Tier | Price compared with Standard | What you get | Use it for |
|---|---|---|---|
| Standard | Normal pay-per-token | Default speed, no commitment | The live API, where a user waits for the answer |
| Flex | About 50% cheaper | Lower priority: can be slower or queued when AWS is busy | Work nobody waits on: loading documents, evaluation runs |
| Priority | About 75% more expensive | Requests served first, fast even at busy times | Production apps where speed matters more than cost |
| Reserved | Depends on the commitment | A fixed amount of capacity committed for a period | Large, steady, predictable traffic |

- **Batch inference** is a separate mode: submit many requests at once and
  collect the results later, at about half the Standard price.
- **For this project:** Standard for `/api/ask` and chat; Flex or batch for
  ingestion and evaluations; ignore Priority and Reserved.
- **Before relying on a tier:** check the model's row on the
  [Bedrock pricing page](https://aws.amazon.com/bedrock/pricing/). Not every
  model offers every tier, and the Reserved terms need confirming there.
