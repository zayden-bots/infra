#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$(dirname "$ROOT")"

for repo in schema platform modules bots dashboard; do
  if [ ! -e "$PARENT/$repo" ]; then
    git clone "https://github.com/zayden-bots/$repo" "$PARENT/$repo"
  else
    echo "$repo: present"
  fi
done

for repo in bots dashboard; do
  link="$PARENT/$repo/config.toml"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "$repo: config.toml is a regular file, left alone" >&2
    continue
  fi
  ln -sfn "../$(basename "$ROOT")/config/zayden.toml" "$link"
done
