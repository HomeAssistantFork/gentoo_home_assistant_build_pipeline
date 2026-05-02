#!/bin/bash
set -euo pipefail
BASE="/mnt/c/Users/tamus/projects/linux/home_assistant_1/repos/home-assistant"

# Ensure gh is available
if ! command -v gh &>/dev/null; then
  echo "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list
  apt-get update -qq && apt-get install -y -qq gh
fi

# Check auth status; prompt login if not authenticated
if ! gh auth status &>/dev/null; then
  echo "GitHub CLI not authenticated. Launching interactive login..."
  gh auth login --hostname github.com --git-protocol https --web
fi

# Wire gh as Git credential helper so pushes use the stored token
gh auth setup-git

for r in buildroot brands android addons; do
  p="$BASE/$r"
  fork="https://github.com/HomeAssistantFork/${r}.git"
  upstream_url="https://github.com/home-assistant/${r}.git"
  echo "=== $r ==="

  git -C "$p" remote set-url origin "$fork"

  if ! git -C "$p" remote get-url upstream &>/dev/null; then
    git -C "$p" remote add upstream "$upstream_url"
  fi

  if [ -f "$p/.git/shallow" ]; then
    echo "  Unshallowing from upstream..."
    git -C "$p" fetch --unshallow upstream
  fi

  branch=$(git -C "$p" rev-parse --abbrev-ref HEAD)
  echo "  Pushing branch: $branch to $fork"
  if git -C "$p" push -u origin "$branch"; then
    echo "  PUSH_OK"
  else
    echo "  PUSH_FAILED"
  fi
  echo "=== END $r ==="
done
