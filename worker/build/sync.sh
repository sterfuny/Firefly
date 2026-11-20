#!/usr/bin/env bash
set -e

git remote set-url origin \
"https://sterfuny:${GITHUB_TOKEN}@github.com/sterfuny/Firefly.git"
git config user.name "cloudflare[bot]"
git config user.email ""

CURRENT_BRANCH="${WORKERS_CI_BRANCH:-main}"
echo "Current Triggered Branch: ${CURRENT_BRANCH}"

if git ls-remote --exit-code --heads origin content; then
  echo "Pulling content branch, merging origin/${CURRENT_BRANCH} into content..."
  
  # fetch 分支
  git fetch origin content
  git fetch origin ${CURRENT_BRANCH}
  # 强制切出并重置本地 content 跟踪远端 content（避免 fetch 冲突）
  git checkout -B content origin/content
  
  # 确保远端主分支存在后再合并，使用 origin/${CURRENT_BRANCH}
  if git rev-parse --verify "origin/${CURRENT_BRANCH}" >/dev/null 2>&1; then
    echo "Merging origin/${CURRENT_BRANCH}..."
    git merge "origin/${CURRENT_BRANCH}" -X theirs
  else
    echo "Warning: origin/${CURRENT_BRANCH} not found, skipping merge."
  fi
else
  echo "Initializing content branch..."
  git checkout -b content
fi

echo "Running pull-r2..."
node worker/build/pull-r2.js

echo "Running build..."
pnpm build

echo "Committing changes..."
git add src/content
# 如果没有内容变化，git commit 会报错退出
git commit -m "Sync R2 (Build Verified)" || echo "No changes to commit"

echo "Pushing to origin content..."
git push -f origin content || echo "Push failed, continuing deployment..."
