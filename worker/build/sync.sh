git remote set-url origin \
"https://sterfuny:${GITHUB_TOKEN}@github.com/sterfuny/Firefly.git" && \

node worker/build/pull-r2.js && \
pnpm build && \

git config user.name "get1Mster" && \
git config user.email "97845248+get1Mster@users.noreply.github.com" && \

if git ls-remote --exit-code --heads origin content; then
  echo "pull content breach, merge mastar and content..."
  git fetch origin content:content
  git checkout content
else
  echo "null content breach, init content commit..."
  git checkout -b content
fi && \

git merge master -m "Merge master and Sync R2" -X theirs || true && \

git add src/content && \
git commit -m "Sync R2" || true && \

git push origin content
