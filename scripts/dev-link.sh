#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$ROOT")"

TARGET="$PARENT/.cargo/config.toml"
MARKER="# managed by infra/scripts/dev-link.sh"

has_marker() {
  local first
  IFS= read -r first < "$TARGET" || true
  [ "$first" = "$MARKER" ]
}

case "${1:-}" in
  on)
    if [ -e "$TARGET" ] && ! has_marker; then
      echo "dev-link: foreign config at $TARGET" >&2
      exit 1
    fi
    mkdir -p "$PARENT/.cargo"
    cp "$ROOT/template/dev-patch.toml" "$TARGET"
    echo "dev-link: on"
    ;;
  off)
    if [ ! -e "$TARGET" ]; then
      echo "dev-link: off"
      exit 0
    fi
    if ! has_marker; then
      echo "dev-link: foreign config at $TARGET" >&2
      exit 1
    fi
    rm "$TARGET"
    rmdir "$PARENT/.cargo" 2> /dev/null || true
    echo "dev-link: off"
    ;;
  status)
    if [ ! -e "$TARGET" ]; then
      echo "dev-link: off"
    elif has_marker; then
      echo "dev-link: on"
    else
      echo "dev-link: foreign config at $TARGET"
      exit 1
    fi
    ;;
  *)
    echo "usage: dev-link.sh on|off|status" >&2
    exit 2
    ;;
esac
