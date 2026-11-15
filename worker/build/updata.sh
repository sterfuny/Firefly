node scripts/pull-r2.js && \

git config user.name "Cloudflare Build Bot" && \
git config user.email "bot@cloudflare.com" && \

if git ls-remote --exit-code --heads origin content; then
  echo "pull content breach, merge main and content..."
  git fetch origin content:content
  git checkout content
else
  echo "null content breach, init content commit..."
  git checkout -b content
fi && \

git merge main -m "chore: auto merge main" -X theirs || true && \

git add src/content && \
git commit -m "chore: auto sync R2" || true && \

git push origin content && \
pnpm build
