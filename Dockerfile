# One Step At A Time API. The same image runs locally, on AWS Lambda (through
# the AWS Lambda Web Adapter) and, later, on ECS Fargate or EC2.
#
#   docker build --build-arg APP_VERSION=local -t one-step-api .
#   docker run --rm -p 8000:8000 one-step-api
#
# Behind an HTTPS-inspecting proxy (Zscaler on the dev PC), add a CA bundle
# that includes the proxy's root; it is used by pip only, never stored:
#   docker build --secret id=ca,src=$env:USERPROFILE\certs\zscaler-ca-bundle.pem ...

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
