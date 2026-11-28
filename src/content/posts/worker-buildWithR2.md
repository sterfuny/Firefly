---
title: 基于 Cloudflare 的自动化静态内容发布
published: 2026-11-19
updated: 2026-11-26
description: 通过R2保存构建静态资源时需要的内容，在平台同时依赖Queue和remote仓库获得更快更及时的构建
tags:
  - Cloudflare
  - R2
  - Worker
  - git
category: 指南
draft: false
---
在现代静态站点的开发流程中，实现内容与代码的解耦、自动化构建，可以提升人的心情和项目的可观性。

本文将详细介绍如何利用 Cloudflare Serverless 生态构建这样一套流水线：以 **R2** 作为对象存储，通过 **Worker** 消费 **Queue** 触发 **Workers Builds** 阶段利用 Git 的底层机制实现极其简单的增量备份。

## 流程图

```mermaid
flowchart LR
    subgraph Cloudflare
        B -->|生产| queue
        queue[Queue] -->|消费| D
        D -->|POST| E
        E -.->|构建事务| F[dist]
        F -.->|deploy| D
        F -.-|add content| new[commit]
    end
    
    B[(R2 bucket)]
    D[Worker]
    E[Workers Builds]
    
    subgraph local
        content([content])
        src([stc])
    end
    
    content ==>|上传| B
    src ==>|push| repo
    repo[GitHub] -->|POST| E
    new ==>|push| repo
```

---

## 准备

### R2 对象存储
使用 Cloudflare R2 作为静态资源的源数据仓库。在构建阶段，通过 node.js 脚本（如 AWS SDK）连接 R2，并将所需的变量 `R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY`、`R2_BUCKET_NAME` 等注入到构建环境变量或密钥中。

> [!tip]
> 开通对象存储需要绑定支付方式
> 2026的Cloudflare支持银联，PayPal或银行卡都可用

### Queue 接收 R2 生产消息
上传存储桶时，让R2将 `ObjectCreated:*` 其中包括 `PutObject`、`CopyObject`、`CompleteMultipartUpload` 这些对象事件生产到队列。

面板的Queue设置没有关于存储桶的细节生产消息，只能通过cli来应用设置

```bash 
wrangler r2 bucket notification create [桶名称] \
  --event-type object-create \
  --queue [队列名称]
```

> [!note]
> 如果你在R2设置页里直接探索，也能找到一个付费的事件通知选项，但它适用于平台外的钩子

### Worker 消费 Queue
在配置文件内绑定队列和消费设置，由于 Worker 的机制不能直接消费 **Workers Builds** ，所以需要当收到 **Queue** 消息时的函数，直接 POST 在设置页里钩子来间接的触发

::: code-group

```json title="wrangler.jsonc"
{
  // ...
  "queues": {
    "consumers": [
      {
        "queue": "content-build",
        "max_batch_size": 100,
        "max_batch_timeout": 60
      }
    ]
  },
  // ...
}
```

```javascript title="worker.js"
export default {
  async queue(batch, env, ctx) {
    console.log(`Received ${batch.messages.length} R2 update notifications, preparing to trigger build...`);
    try {
      const res = await fetch(env.DEPLOY_HOOK_URL, { 
        method: "POST" 
      });
      if (!res.ok) {
        throw new Error(`build error: ${res.status}`);
      }
      console.log("trigger hook");      
      for (const msg of batch.messages) {
        msg.ack();
      }
    } catch (err) {
      console.error("cant hook:", err);      
      for (const msg of batch.messages) {
        msg.retry({ delaySeconds: 60 });
      }
    }
  }
};
```

:::

### repo 令牌
在仓库平台 Add token，申请对应权限以便可以提交和拉取。

## git 备份策略

在 Workers Builds 中实现自动备份时，会面临构建环境的浅克隆限制。环境默认不包含完整历史，初次`git merge`能够成功，因为`content`没有历史提交可以直接指向主分支提交，但下次进行会因为`content`的新提交没有直接联系，git 不允许合并两个完全没有共同提交历史的分支，以防止误操作。因为merge有各种不确定的因素，改用更直接的提交方式。

为了保持备份分支 `content` 的纯粹，我们需要在两种情况下做出不同的流程

*   **首次初始化**：解除 CI 环境的浅克隆，找到主分支的初始提交。利用 `git reset --soft` 将 HEAD 指针移动至此，保留当前工作区的最新文件，然后直接提交。这样分支可以直接指向它。
*   **常规更新**：拉取 `content` 分支，同样利用 `git reset --soft` 将 HEAD 移至远端 `content` 的最新提交，工作区保留当前 CI 拉取的最新主分支代码，随后直接 commit 并强推。

> [!tip]
> 初始化时假设初始提交是压缩的模板提交，期望它是站点模板迭代完善的提交，否则以最新的提交为新分支的根最好

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