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
  ln -sfn ../infra/config/zayden.toml "$PARENT/$repo/config.toml"
done
