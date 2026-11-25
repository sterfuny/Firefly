---
title: 基于 Cloudflare 的自动化静态内容发布
published: 2026-11-16
updated: 2026-11-23
description: 通过R2保存构建静态资源时需要的内容，在Cloudflare平台同时依赖Queue和GitHub获得更快更及时的构建
tags:
  - Cloudflare
  - R2
  - worker
  - git
category: 指南
draft: false
---
在现代静态站点的开发流程中，实现内容与代码的解耦、自动化构建，可以提升人的心情和项目的可观性。

本文将详细介绍如何利用 Cloudflare Serverless 生态构建这样一套流水线：以 **R2** 作为对象存储，通过 **Queue** 与 **Worker** 触发构建，并在 **Workers CI** 阶段利用 Git 的底层机制实现极其简单的增量备份。

## 流程图

```mermaid
flowchart TD
    A -->|上传| B
    B -->|生产| queue
    queue[CF Queue] -->|消费| D
    D -->|POST| E
    E -->|构建事务| F[dist]
    F -->|deploy| G[CF]
    
    E -.->|git reset --soft| I[content breach]
    
    A[content]
    B[R2 bucket]
    D[CF Worker]
    E[CF CI]
    
    src --> |push| repo
    repo[GitHub] -->|POST| E
```

---

## 准备

### R2 内容存储
使用 Cloudflare R2 作为静态资源的源数据仓库。在 CI 构建阶段，通过 Node.js 脚本（如 AWS SDK）连接 R2，并将所需的变量 `R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY`、`R2_BUCKET_NAME` 等注入到构建环境变量或密钥中。

### Queue 与 Worker 构建触发
为避免直接通过 R2 的高频事件调用 Webhook 导致请求堆积，引入 Cloudflare Queues 进行削峰填谷。Worker 消费队列消息，并发起构建请求。

### repo 令牌
在对应平台 Add token ，申请对应权限以便可以提交和查看。

## 参考

```json title="wrangler.toml"
{
  "name": "name",
  "main": "./worker/worker.js",
  "compatibility_date": "2026-10-01",
  "compatibility_flags": [
    "nodejs_compat"
  ],
  "assets": {
    "directory": "./dist"
  },
  "queues": {
    "consumers": [
      {
        "queue": "r2-content-build",
        "max_batch_size": 100,
        "max_batch_timeout": 60
      }
    ]
  },
  // ...
}
```

---

```javascript
export default {
  async queue(batch, env, ctx) {
    try {
      const res = await fetch(env.DEPLOY_HOOK_URL, { method: "POST" });
      if (!res.ok) throw new Error(`Hook failed: ${res.status}`);
      for (const msg of batch.messages) msg.ack();
    } catch (err) {
      console.error("Trigger failed:", err.message);
      for (const msg of batch.messages) msg.retry({ delaySeconds: 60 });
    }
  }
};
```

## git 备份策略

在 CI 流水线中实现自动备份时，会面临构建环境的浅克隆限制。环境默认不包含完整历史，初次`git merge`能够成功，因为`content`没有历史提交可以直接指向主分支提交，但下次进行会因为`content`的新提交没有直接联系，git 不允许合并两个完全没有共同提交历史的分支，以防止误操作。因为merge有各种不确定的因素，改用更直接的提交方式。

为了保持备份分支 `content` 的纯粹，我们需要在两种情况下做出不同的流程

*   **首次初始化**：解除 CI 环境的浅克隆，找到主分支的初始提交。利用 `git reset --soft` 将 HEAD 指针移动至此，保留当前工作区的最新文件，然后直接提交。这样分支可以直接指向它。
*   **常规更新**：拉取 `content` 分支，同样利用 `git reset --soft` 将 HEAD 移至远端 `content` 的最新提交，工作区保留当前 CI 拉取的最新主分支代码，随后直接 commit 并强推。

> [!tip]
> 初始化时假设主分支是压缩的模板提交，根提交后的改动较少时建议采用，否则以最新的提交为新分支的根最好

### 构建脚本

```bash
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

# 拉取 R2 内容并构建
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
```

至于`pull-r2.js`的内容就省略不记了，这是将 R2 下载后放置到`src/content/`的内容。经过编写后可以根据`content`查看改动历史，同时省去了繁琐的本地手动提交。