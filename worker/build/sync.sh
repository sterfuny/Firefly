#!/usr/bin/env bash
set -e

git remote set-url origin "https://sterfuny:${GITHUB_TOKEN}@github.com/sterfuny/Firefly.git"
git config user.name "cloudflare[bot]"
git config user.email ""

if git ls-remote --exit-code --heads origin content > /dev/null 2>&1; then
  # 远端已有 content 分支
  echo "Updating existing content branch..."
  git fetch origin content
  
  git reset --soft origin/content
  git checkout -B content
  
else
  # 远端没有 content 分支
  echo "Initializing content branch from ROOT commit (only once)..."
  
  # 获取完整历史
  git fetch --unshallow || git fetch --depth=1000000
  ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD | tail -n 1)
  echo "Root commit found: ${ROOT_COMMIT}"
  
  # 移动 HEAD 指针到根提交
  git reset --soft "${ROOT_COMMIT}"
  git checkout -B content
fi

# 2. 拉取 R2 内容并构建
echo "Running pull-r2..."
node worker/build/pull-r2.js
CURRENT_TIME=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S (UTC+8)')

echo "Running build..."
pnpm build

echo "Committing changes..."
git add src/content
git commit -m "Sync R2 ${CURRENT_TIME}" || echo "No changes to commit"

echo "Pushing to origin content..."
git push -f origin content || echo "Push failed, continuing deployment..."

echo "Done!"
