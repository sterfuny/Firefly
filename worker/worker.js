export default {
  async queue(batch, env, ctx) {
    console.log(`Received ${batch.messages.length} R2 update notifications, preparing to trigger build...`);

    try {
      // 环境变量 DEPLOY_HOOK_URL 需要在 Cloudflare 控制台的 Worker 设置里配置好
      const res = await fetch(env.DEPLOY_HOOK_URL, { 
        method: "POST" 
      });

      if (!res.ok) {
        throw new Error(`触发构建失败，状态码: ${res.status}`);
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
