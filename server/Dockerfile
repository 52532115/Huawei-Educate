# SafeTAcademy AI 后端。
#
# 注意这里**没有 `npm install`**：服务端是零依赖的（只用 node:http + 全局 fetch），
# 所以也没有 node_modules。这不是省事，是刻意的——一个持有厂商密钥的组件
# 不该引入供应链面。加依赖前请先想清楚这一点。
#
# 构建：  docker build -t safeta-ai-backend:1.0.0 .
# 或直接用 ../docker-compose.yml。

FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

# 只带运行期需要的东西。测试、夹具、反代配置都不进镜像。
COPY package.json ./
COPY src ./src
COPY scripts ./scripts

# 官方镜像自带 uid 1000 的 node 用户。容器里不需要 root 做任何事。
# 配合 compose 的 read_only + cap_drop: ALL，进程既写不了磁盘也拿不到额外能力。
USER node

EXPOSE 8787

# 探活打的是本机回环，容器内一定可达；端口跟随 PORT。
# 用 node 而不是 wget/curl：镜像里本来就有 node，不必再装包。
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# 直接起 node，不经过 npm——少一层 shell 转发，信号（SIGTERM）才能直达。
# src/index.js 自己处理 SIGINT/SIGTERM 并优雅关闭。
ENTRYPOINT ["node", "src/index.js"]
