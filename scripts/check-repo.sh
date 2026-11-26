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
