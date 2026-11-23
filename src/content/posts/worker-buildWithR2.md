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
在现代静态站点的开发流程中，实现内容与代码的解耦、自动化构建以及高效的版本备份，是提升工程化水平的重要环节。

本文将详细介绍如何利用 Cloudflare Serverless 生态构建这样一套流水线：以 **R2** 作为对象存储，通过 **Queue** 与 **Worker** 触发构建，并在 **Workers CI** 阶段利用 Git 的底层机制实现极其轻量、高效的增量备份。

## 架构设计图

```mermaid
graph TD
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
    
    src --> |push| git
    git[GitHub] -->|POST| E
```

---

## Cloudflare准备

### 1. R2 内容存储
使用 Cloudflare R2 作为静态资源（Markdown、图片等）的源数据仓库。在 CI 构建阶段，通过 Node.js 脚本（如 AWS SDK）连接 R2，并将所需的变量（`R2_ACCESS_KEY_ID`、`R2_SECRET_ACCESS_KEY`、`R2_BUCKET_NAME` 等）注入到构建环境中。

### 2. Queue 与 Worker 构建触发
为避免直接通过 R2 的高频事件调用 Webhook 导致请求堆积，引入 Cloudflare Queues 进行削峰填谷。Worker 消费队列消息，并发起构建请求。

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

---

## 二、 Git 增量备份策略

在 CI 流水线中实现自动备份时，通常会面临两个技术难点：
1. **CI 环境的浅克隆限制**：环境默认不包含完整历史，直接进行分支合并（Merge）容易产生引用丢失或历史断代。
2. **仓库体积膨胀**：如果主分支（master）的初始提交（Root Commit）包含了大量文件，而备份分支每次初始化都创建孤儿提交，将导致 `.git` 目录无限膨胀。

### 核心思路：利用 Root Commit 与 `reset --soft`
为了保持备份分支 `content` 的纯粹与轻量，策略如下：
*   **首次初始化**：解除 CI 环境的浅克隆，找到主分支的 Root Commit（最庞大的初始提交）。利用 `git reset --soft` 将 HEAD 指针移动至此，保留当前工作区的最新文件，然后直接提交。这样备份分支的历史直接挂载在 Root Commit 下，后续全为极小的增量。
*   **常规更新**：拉取 `content` 分支，同样利用 `git reset --soft` 将 HEAD 移至远端 `content` 的最新提交，工作区保留当前 CI 拉取的最新主分支代码，随后直接 Commit 并强推。

> [!tip]
> 初始化时假设主分支是压缩的模板提交，根提交后的改动较少时建议采用，否则以最新的提交为新分支的根最好

### 构建脚本

```bash
#!/usr/bin/env bash
set -e

# 1. 初始化 Git 配置
git remote set-url origin "https://sterfuny:${GITHUB_TOKEN}@github.com/sterfuny/Firefly.git"
git config user.name "cloudflare[bot]"
git config user.email "cloudflare[bot]@users.noreply.github.com"

if git ls-remote --exit-code --heads origin content > /dev/null 2>&1; then
  # ─── 常规更新：远端已存在 content 分支 ───
  echo "Updating existing content branch..."
  git fetch origin content
  
  # 将 HEAD 移至 content 最新提交，保留当前工作区最新代码
  git reset --soft origin/content
  git checkout -B content
  
else
  # ─── 首次初始化：远端无 content 分支 ───
  echo "Initializing content branch from ROOT commit..."
  
  # 解除浅克隆以获取完整历史，寻找起点
  git fetch --unshallow || git fetch --depth=1000000
  
  # 查找根提交 (最旧的一个提交)
  ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD | tail -n 1)
  echo "Root commit found: ${ROOT_COMMIT}"
  
  # 将 HEAD 移至根提交，保留当前工作区最新代码
  git reset --soft "${ROOT_COMMIT}"
  git checkout -B content
fi

# 2. 内容拉取与构建
echo "Running pull-r2..."
node worker/build/pull-r2.js

echo "Running build..."
pnpm build

# 3. 生成东八区时间戳
CURRENT_TIME=$(TZ='Asia/Shanghai' date '+%Y-%m-%d %H:%M:%S (UTC+8)')

# 4. 提交与推送备份
echo "Committing changes..."
git add src/content
git commit -m "Sync R2 at ${CURRENT_TIME} (Build Verified)" || echo "No changes to commit"

echo "Pushing to origin content..."
git push -f origin content || echo "Push failed, continuing deployment..."

echo "Done!"
```

### 方案分析
1. **防止大量重复 diff**：首次初始化利用 `reset --soft` 指向已存在的 Root Commit，Git 底层不会重复存储其包含的大文件。后续更新基于同一条历史线追加，也方便复盘部署间的不同更改。
2. **工作区状态隔离**：`reset --soft` 移动了 Git 指针，还原也不会冲突工作区，确保构建所用的代码是 CI 拉取的 git 提交和内容。
3. **规避合并冲突**：摒弃了脆弱的 `git merge` 操作，依靠强制推送 `push -f` 保证分支流程不出现错误。
4. **时间记录明确**：利用系统环境变量 `TZ='Asia/Shanghai'` 获取准确的东八区时间，便于审计每次备份的触发时间。

## 总结
该方案通过 R2 与 Cloudflare 队列体系实现了触发与构建的解耦。同时，在 Git 自动化方面，巧妙运用 `git reset --soft` 机制，在规避 CI 浅克隆限制的同时，解决了初始大文件导致的仓库体积膨胀问题，实现了高效、安全的增量备份。