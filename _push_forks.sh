#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/c/Users/tamus/projects/linux/home_assistant_1/repos/home-assistant"
export GIT_TERMINAL_PROMPT=0

repos=(version operating-system buildroot brands android addons)

for r in "${repos[@]}"; do
  case "$r" in
    version) url="https://github.com/HomeAssistantFork/version.git" ;;
    operating-system) url="https://github.com/HomeAssistantFork/operating-system.git" ;;
    buildroot) url="https://github.com/HomeAssistantFork/buildroot.git" ;;
    brands) url="https://github.com/HomeAssistantFork/brands.git" ;;
    android) url="https://github.com/HomeAssistantFork/android.git" ;;
    addons) url="https://github.com/HomeAssistantFork/addons.git" ;;
  esac

  p="$ROOT/$r"
  echo "=== BEGIN $r ==="
  if [[ ! -d "$p/.git" ]]; then
    echo "MISSING_GIT_REPO $p"
    echo "=== END $r ==="
    continue
  fi

  git -C "$p" remote set-url origin "$url"
  echo "origin=$(git -C "$p" remote get-url origin)"

  if [[ -n "$(git -C "$p" status --porcelain)" ]]; then
    if git -C "$p" add -A; then
      if [[ -n "$(git -C "$p" diff --cached --name-only)" ]]; then
        git -C "$p" commit -m "GentooHA: apply local changes" || true
      else
        echo "NO_STAGEABLE_CHANGES"
      fi
    else
      echo "ADD_FAILED"
      git -C "$p" status --porcelain | head -n 20 || true
    fi
  else
    echo "NO_LOCAL_CHANGES"
  fi

  if git -C "$p" push -u origin HEAD; then
    echo "PUSH_OK"
  else
    echo "PUSH_FAILED"
  fi
  echo "=== END $r ==="
done
