git remote set-url origin \
"https://sterfuny:${GITHUB_TOKEN}@github.com/sterfuny/Firefly.git"
git config user.name "get1Mster"
git config user.email "97845248+get1Mster@users.noreply.github.com"
CURRENT_BRANCH=${WORKERS_CI_BRANCH};

if git ls-remote --exit-code --heads origin content; then
  echo "pull content branch, merge ${CURRENT_BRANCH} and content..."
  git fetch origin content:content
  git checkout content
  # 把主分支最新代码合并进 content
  git merge ${CURRENT_BRANCH} -X theirs
else
  echo "init content branch..."
  git checkout -b content
fi && \

node worker/build/pull-r2.js && \
pnpm build && \

git add src/content && \
git commit -m "Sync R2 (Build Verified)"

git push origin content
