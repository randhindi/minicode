#!/usr/bin/env bash
set -euo pipefail
# Deploy the build
TARGET="${1:-staging}"
deploy() {
  local dir=$HOME/app
  if [[ -d "$dir" ]]; then
    echo "Deploying to $TARGET from ${dir}" | tee -a deploy.log
  fi
}
for f in *.tar.gz; do deploy "$f"; done
