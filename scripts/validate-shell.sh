#!/usr/bin/env bash
set -euo pipefail

files=()
while IFS= read -r file; do
  files+=("$file")
done < <(find scripts -type f -name '*.sh' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  printf '[error] no shell scripts found for validation\n' >&2
  exit 1
fi

for file in "${files[@]}"; do
  bash -n "$file"
done

printf '[ok] shell syntax passed for %s file(s)\n' "${#files[@]}"
