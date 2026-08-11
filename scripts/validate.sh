#!/usr/bin/env bash
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

run() {
  printf '\n==> %s\n' "$1"
  shift
  "$@"
}

run "Verify required tools" bash scripts/verify-tools.sh
run "Validate repository structure" bash scripts/validate-structure.sh
run "Validate Markdown" ruby scripts/validate-markdown.rb
run "Validate YAML" ruby scripts/validate-yaml.rb
run "Validate shell syntax" bash scripts/validate-shell.sh

if command -v shellcheck >/dev/null 2>&1; then
  run "Run ShellCheck" shellcheck scripts/*.sh
else
  printf '\n==> ShellCheck not installed; optional local check not executed\n'
fi

if command -v actionlint >/dev/null 2>&1; then
  run "Run actionlint" actionlint
else
  printf '\n==> actionlint not installed; optional local check not executed\n'
fi

printf '\nAll required Stage 1 validation checks passed.\n'
