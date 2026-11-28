---
title: 初见obsidian
published: 2026-11-25
description: 想起来给自己做个博客，才觉得需要一个趁手的写作工具，于是想到了三年前比较火的obsidian的obsidian
tags:
  - Blog
  - Obsidian
category: 评测
draft: false
---
经过网络挖掘后，才发现这不是一个简单的 markdown 编辑器，如同 vscode 一样的社区**插件市场**，插件都是发布前渲染过的，插件核心是两个文件 js 和 css，这样节省了文件 io。

先看看**安装包**的体积表现

```bash
$ ls -lh
总计 139M
-rw-rw-r-- 1 msterfuny msterfuny  15M 11月26日 09:05 Obsidian-1.15.1.apk
-rw-rw-r-- 1 msterfuny msterfuny 125M 11月26日 09:05 obsidian-1.15.1.tar.gz
```

> [!note]
> linux 约 125 mb，windows 约 235 mb，移动端约 15 mb

在桌面端为了能够进行服务器才能运行的 nodejs 操作，直接变成了 electron 结构，而移动端上直接复用 webview，则省去了很多体积，也舍弃了重型前端服务，扁平的设计结构提供了更大的定制空间。

我之前没用过这类软件，没有写字整理思绪的习惯，一般都是复制别人的话或是资源地址，卡片风格带标签的备忘录，第一次用这种文件系统的风格的笔记工具，而且 markdown 类型能符合开发者习惯，也有适合前端获取信息的 Frontmatter 字段。

