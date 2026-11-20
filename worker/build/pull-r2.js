import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import fs from "node:fs";
import path from "node:path";

// 初始化 S3 客户端
const s3 = new S3Client({
  region: "auto",
  endpoint: process.env.R2_ENDPOINT,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
});

const BUCKET = process.env.R2_BUCKET_NAME;
const TARGET_DIR = path.join(process.cwd(), "src/content");

async function pull() {
  console.log(`开始从 R2 [${BUCKET}] 拉取文件...`);
  
  let continuationToken = undefined;
  let totalFiles = 0;

  do {
    // 每次拉取 1000 个对象的列表
    const listRes = await s3.send(
      new ListObjectsV2Command({
        Bucket: BUCKET,
        ContinuationToken: continuationToken,
      })
    );

    if (listRes.Contents && listRes.Contents.length > 0) {
      // 并发下载当前批次的所有文件
      await Promise.all(
        listRes.Contents.map(async (obj) => {
          // 跳过文件夹占位符
          if (obj.Key.endsWith("/")) return;

          const filePath = path.join(TARGET_DIR, obj.Key);
          
          // 确保本地目标文件夹存在
          fs.mkdirSync(path.dirname(filePath), { recursive: true });

          // 下载文件
          const getRes = await s3.send(
            new GetObjectCommand({
              Bucket: BUCKET,
              Key: obj.Key,
            })
          );

          // 将文件流转换为 Buffer 并写入本地磁盘
          const buffer = await getRes.Body.transformToByteArray();
          fs.writeFileSync(filePath, buffer);
          
          console.log(`[下载] ${obj.Key}`);
        })
      );
      totalFiles += listRes.Contents.length;
    }

    continuationToken = listRes.NextContinuationToken;
  } while (continuationToken);

  console.log(`✅ R2 拉取完成，共处理 ${totalFiles} 个文件。`);
}

pull().catch((err) => {
  console.error("❌ 拉取 R2 失败:", err);
  process.exit(1); // 退出码 1 会中断后续的构建命令
});
