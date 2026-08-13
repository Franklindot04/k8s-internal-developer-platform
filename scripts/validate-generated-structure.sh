#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$(git rev-parse --show-toplevel)}"
SERVICES_DIR="$ROOT/services"
OWNERSHIP_MARKER="# Generated from ../service.yaml by the platform self-service generator.
# Do not edit directly; update the PlatformService specification instead."

failures=0

fail_with() {
  printf '[error] %s\n' "$1" >&2
  failures=1
}

validate_generated_dir() {
  service_dir="$1"
  generated_dir="$service_dir/generated"
  service_name="$(basename "$service_dir")"
  relative_prefix="services/$service_name/generated"

  if [ -L "$generated_dir" ]; then
    fail_with "$relative_prefix must not be a symlink"
    return
  fi

  if [ ! -e "$generated_dir" ]; then
    return
  fi

  if [ ! -d "$generated_dir" ]; then
    fail_with "$relative_prefix must be a directory"
    return
  fi

  if [ ! -f "$service_dir/service.yaml" ] || [ -L "$service_dir/service.yaml" ]; then
    fail_with "generated artifacts require canonical source: services/$service_name/service.yaml"
  fi

  for entry in "$generated_dir"/* "$generated_dir"/.[!.]* "$generated_dir"/..?*; do
    [ -e "$entry" ] || [ -L "$entry" ] || continue
    case "$(basename "$entry")" in
      values.yaml | application.yaml)
        ;;
      *)
        fail_with "unexpected persistent generated artifact: $relative_prefix/$(basename "$entry")"
        ;;
    esac
  done

  for name in values.yaml application.yaml; do
    target="$generated_dir/$name"
    relative="$relative_prefix/$name"
    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
      fail_with "generated artifact pair is incomplete: missing $relative"
      continue
    fi
    if [ -L "$target" ]; then
      fail_with "$relative must not be a symlink"
      continue
    fi
    if [ ! -f "$target" ]; then
      fail_with "$relative must be a regular file"
      continue
    fi
    marker="$(sed -n '1,2p' "$target")"
    if [ "$marker" != "$OWNERSHIP_MARKER" ]; then
      fail_with "$relative is not a platform-owned generated artifact"
    fi
  done
}

if [ -d "$SERVICES_DIR" ]; then
  for service_dir in "$SERVICES_DIR"/*; do
    [ -d "$service_dir" ] || [ -L "$service_dir/generated" ] || continue
    validate_generated_dir "$service_dir"
  done
fi

if [ "$failures" -ne 0 ]; then
  exit 1
fi

printf '[ok] generated service artifact structure passed\n'
