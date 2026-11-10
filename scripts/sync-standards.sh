#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$ROOT")"

check=0
case "${1:-}" in
  "") ;;
  --check) check=1 ;;
  *)
    echo "usage: sync-standards.sh [--check]" >&2
    exit 2
    ;;
esac
if [ "$#" -gt 1 ]; then
  echo "usage: sync-standards.sh [--check]" >&2
  exit 2
fi

pairs=(
  "rust-toolchain.toml:rust-toolchain.toml"
  "rustfmt.toml:rustfmt.toml"
  "clippy.toml:clippy.toml"
  "cargo-config.toml:.cargo/config.toml"
)

drifted=0
for repo in schema platform modules bots dashboard; do
  if [ ! -d "$PARENT/$repo" ]; then
    echo "$repo: missing"
    continue
  fi
  for pair in "${pairs[@]}"; do
    src="$ROOT/template/${pair%%:*}"
    dest="${pair#*:}"
    if [ "$check" -eq 1 ]; then
      if ! diff -u "$PARENT/$repo/$dest" "$src"; then
        echo "drift: $repo/$dest"
        drifted=1
      fi
    else
      mkdir -p "$(dirname "$PARENT/$repo/$dest")"
      cp "$src" "$PARENT/$repo/$dest"
    fi
  done
done

exit "$drifted"
