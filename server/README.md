# SafeTAcademy AI 后端（`/embed` + 聊天代理）

一个**零依赖**的 Node HTTP 服务：把「模型密钥」从客户端彻底挪到服务端。

它存在的直接原因是 `AI功能测试报告_2026-07-15.md` 里的 **P0 / AI-SEC-001**：
客户端不得持有厂商密钥。这一条此前只完成了一半（密钥没进构建产物，但仍存在设备上）。
本服务补上另一半——客户端只持有**自己的应用令牌**，厂商密钥只存在于服务端进程的环境变量里。

同时它也解决了一个现实问题：DeepSeek 没有 embedding 接口，向量检索需要一个
第三方 embedding 提供商。把这家provider的密钥也放在客户端，等于把 P0 的窟窿再捅一次。

## 两个上游，彼此独立

| 能力 | 路径 | 上游 | 未配置时 |
| --- | --- | --- | --- |
| 聊天 | `/v1/chat/completions`、`/chat/completions`、`/chat` | `CHAT_*` | 503 |
| 向量 | `/embed` | `EMBEDDING_*` | 503（客户端退化为纯词法检索，功能不受影响） |
| 健康 | `GET /health` | — | 永远可用 |

聊天与向量**不共用密钥**：一边余额告罄或密钥泄露，不会连带另一边。

## 运行

需要 Node ≥ 18（用到全局 `fetch`）。**没有任何 npm 依赖，也没有 `node_modules`** ——
一个持有凭据的组件不该引入供应链面。因此没有 `npm install` 这一步。

```bash
cd server
cp .env.example .env      # 填入 CHAT_API_KEY / EMBEDDING_API_KEY / APP_TOKEN
set -a && . ./.env && set +a
node src/index.js
```

或直接：

```bash
PORT=8787 APP_TOKEN=dev-token \
CHAT_API_KEY=sk-xxx EMBEDDING_API_KEY=sk-yyy \
node src/index.js
```

启动时会**明确报出**哪些能力没配好（`APP_TOKEN` 未设置会警告认证已关闭）。
每一处缺失都降级为一条干净的 4xx/5xx，而不是崩溃——否则学生看到的第一个现象就是报错。

## 配置项

全部来自环境变量，默认值见 `src/config.js`。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | `8787` | 监听端口 |
| `APP_TOKEN` | 空 | 应用会话令牌。**为空即关闭鉴权**，仅限本机演示 |
| `CHAT_BASE_URL` | `https://api.deepseek.com/v1` | 任何 OpenAI 兼容端点 |
| `CHAT_API_KEY` | 空 | 未配置 → `/chat` 返回 503 |
| `CHAT_MODEL` | `deepseek-flash` | **服务端决定**，客户端不参与 |
| `EMBEDDING_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 任何 OpenAI 兼容端点 |
| `EMBEDDING_API_KEY` | 空 | 未配置 → `/embed` 返回 503 |
| `EMBEDDING_MODEL` | `text-embedding-v3` | 服务端决定 |
| `EMBEDDING_DIMENSION` | `0` | `0` = 信任提供商；非 0 则宽度不符直接拒绝 |
| `EMBEDDING_BATCH_SIZE` | `10` | 每次上游调用的条数（DashScope v3 的上限就是 10） |
| `RATE_LIMIT_PER_MINUTE` | `120` | 固定窗口，按客户端；`0` 关闭 |
| `UPSTREAM_TIMEOUT_MS` | `60000` | 单次上游请求超时 |

`GET /health` 返回的是 `describe()`：**只回答「能不能干活」，不泄露上游地址**，
更不返回任何密钥。

## 接口

### `POST /embed`

```jsonc
// 请求
{ "model": "", "inputs": ["三次握手", "四次挥手"] }

// 200
{ "model": "text-embedding-v3", "dimension": 1024,
  "vectors": [[...], [...]] }        // 与 inputs 一一对应、顺序一致
```

`Authorization: Bearer <APP_TOKEN>`，缺失或错误 → 401。

- `inputs` 超过 `EMBEDDING_BATCH_SIZE` 时服务端**自行分批**，再按 `index` 还原顺序。
  分批是确定性的：条数或宽度对不上就整体拒绝，绝不补齐——向量是**位置敏感**的，
  少一行会让后面所有向量挂到错误的文本块上，比不检索更糟。
- 上限：512 条 / 单条 4000 字符 / 整批 200000 字符 / 请求体 1 MiB。

### `POST /v1/chat/completions`

OpenAI 兼容线协议，`stream: true` 走 SSE 原样转发。服务端只放行白名单字段
（`messages` / `temperature` / `stream` 等），`model` 由服务端决定，客户端指定的
`model`、`api_key` 之类一律忽略。

**流式转发的状态码语义**：上游非 200 时，服务端**在写响应头之前**就把状态码回给客户端，
而不是先 200 再在流中间断开。客户端据此能拿到可读的错误，而不是一个静默截断的答案。
客户端断开时，`AbortSignal` 会传到上游——学生取消提问后，厂商侧不会继续生成、继续计费。

## 客户端怎么用

客户端有且只有一个地方决定「走哪条路」：`features/aiagent/.../service/AiBackend.ets`。

- **后端模式**（配了 Base URL）：所有模型调用打到本服务，头部只带应用令牌。
  设备上**没有任何厂商密钥**。
- **直连模式**（未配 Base URL）：沿用旧行为，用户在设置里填自己的厂商 Key。
  保留它是因为「没有团队后端的学习者也得能用上助教」。

两种模式都是一等公民，**互不静默回退**；也绝不会出现「把厂商 Key 发给自己的后端」
或「把应用令牌发给厂商」——路由只在一处决策。应用侧没有厂商端点常量，
所以换模型 / 换提供商是纯服务端改动。

在 App 的聊天页 ⚙️ 里填 Base URL 与令牌即可切换到后端模式。

## 测试

```bash
cd server
node --test        # 86 个用例：48 单元 + 38 端到端
```

端到端用例会**真起一个服务进程**，配一个桩上游，走真实的鉴权 / 路由 / 中转 / 计费审计路径。
`node --test` 不带路径参数（带目录会被当成文件，报 `MODULE_NOT_FOUND`）。

## 安全说明（改动前请先读）

- **密钥只存在于环境变量**。`describe()`、审计日志、错误响应里都没有密钥，
  上游 Base URL 也不出现在 `/health` 里。
- **不记录请求体**。审计行只有：请求 id、方法、路径、状态码、耗时、客户端标识。
  失败可通过请求 id 与处理器的告警串起来，全程不需要知道学生问了什么。
- **令牌比较是常数时间**（先 SHA-256 再 `timingSafeEqual`），避免按字节比较的时序侧信道。
  同时接受 `Authorization: Bearer` 与 `x-app-token`。
- **限流不信任 `X-Forwarded-For`**，用的是 socket 地址。放在反向代理后面时，
  请让代理自己限流，或改成信任代理头部——**不要**直接相信任意客户端能伪造的头部。
- **审计一条不落**，成功失败都记，一次请求一行。
- 泄露处置：轮换 `APP_TOKEN` 即可让旧客户端失效，**不需要重新发版**。

## 部署

- 对外提供服务前**必须**设置 `APP_TOKEN`。启动日志会警告这一点。
- 放在 TLS 反向代理之后（客户端侧拼的是 `https://`）。
- 建议由进程管理器托管（systemd / Docker），并让它负责注入环境变量。
  本服务不读 `.env` 自身——由你决定怎么把变量喂进来。
- 收到 `SIGINT` / `SIGTERM` 会优雅关闭。

## 未做 / 边界

- **真实 embedding 尚未接进 App**。服务端已经就绪，但客户端默认仍是**纯词法 BM25**。
  这是实测结论，不是遗漏：本地哈希嵌入器与 BM25 等权融合时，Recall@3 从 0.8485
  **掉到** 0.7879 —— 没有语义能力的嵌入当等权伙伴只会挤掉正确结果。
  接上真实嵌入模型后换掉 embedder 即可，RRF 融合层不用动。
- 限流是**进程内**的。多实例部署时每个实例各算一份，需要共享存储才能全局生效。
- 没有做请求级别的用量记账 / 配额（当前只有审计行与限流）。
