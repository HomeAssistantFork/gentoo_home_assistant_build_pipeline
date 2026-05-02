set -euo pipefail
BASE="/mnt/c/Users/tamus/projects/linux/home_assistant_1/repos/home-assistant"
repos=(addons android brands buildroot operating-system version)
for r in "${repos[@]}"; do
  p="$BASE/$r"
  echo "===== $r ====="
  if [ ! -d "$p/.git" ]; then
    echo "MISSING_REPO"
    continue
  fi

  cd "$p"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  echo "BRANCH=$branch"

  git add -A || true

  if [ -n "$(git diff --cached --name-only)" ]; then
    git commit -m "checkin"
    echo "COMMIT=created"
  else
    echo "COMMIT=none"
  fi

  if git push -u origin "$branch"; then
    echo "PUSH=ok"
  else
    echo "PUSH=failed"
  fi

  git status -sb | head -n 3
  echo

done