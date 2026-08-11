#!/usr/bin/env bash
set -euo pipefail

missing=0

require_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '[ok] required tool available: %s\n' "$tool"
  else
    printf '[error] required tool missing: %s\n' "$tool" >&2
    missing=1
  fi
}

note_optional_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    printf '[ok] optional validator available: %s\n' "$tool"
  else
    printf '[info] optional validator not installed: %s\n' "$tool"
  fi
}

require_tool git
require_tool bash
require_tool ruby
require_tool make

note_optional_tool shellcheck
note_optional_tool actionlint

if [ "$missing" -ne 0 ]; then
  printf '[error] required tool verification failed\n' >&2
  exit 1
fi

printf '[ok] required tool verification passed\n'
