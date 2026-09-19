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

### 先体检凭据，再起服务

「填了」和「能用」之间隔着四种失败：密钥少复制了一位、密钥其实是别家产品的、模型名
打错了、账户余额为零。它们**都不会在启动时暴露**——服务照常监听、`/health` 照常 200，
直到第一个学生提问才报 401/402/404。所以部署前先跑一次体检：

```bash
npm run check-upstream               # 读 ./.env，向两家上游各发真实请求
npm run check-upstream -- --offline  # 只做静态核对，一个请求都不发
```

它按顺序回答四个问题：键名有没有写错 → 密钥形状像哪一家 → `GET /models` 认不认这把
密钥、模型名是否真实存在 → 最后发一条 `max_tokens=8` 的消息确认**账户余额够用**。

最后那条是唯一能验出 `402 Insufficient Balance` 的方式。实测踩过：密钥有效、模型名
也在，但账户里没钱，学生端表现就是「AI 一直不回」。表单里看不出来，`/models` 也看不
出来，只有真发一次才知道。

输出里密钥只以掩码 + 指纹出现，可以直接贴进聊天窗口求助。

## 配置项

全部来自环境变量，默认值见 `src/config.js`。

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `PORT` | `8787` | 监听端口 |
| `APP_TOKEN` | 空 | 应用会话令牌。**为空即关闭鉴权**，仅限本机演示 |
| `CHAT_BASE_URL` | `https://api.deepseek.com/v1` | 任何 OpenAI 兼容端点 |
| `CHAT_API_KEY` | 空 | 未配置 → `/chat` 返回 503 |
| `CHAT_MODEL` | `deepseek-flash` | **服务端决定**，客户端不参与 |
| `CHAT_ENABLE_THINKING` | 空 | `true` / `false` / 空。空 = **不发送**该参数，由模型默认值决定 |
| `EMBEDDING_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | 任何 OpenAI 兼容端点 |
| `EMBEDDING_API_KEY` | 空 | 未配置 → `/embed` 返回 503 |
| `EMBEDDING_MODEL` | `text-embedding-v3` | 服务端决定 |
| `EMBEDDING_DIMENSION` | `0` | `0` = 信任提供商；非 0 则宽度不符直接拒绝 |
| `EMBEDDING_BATCH_SIZE` | `10` | 每次上游调用的条数（DashScope v3 的上限就是 10） |
| `RATE_LIMIT_PER_MINUTE` | `120` | 固定窗口，按客户端；`0` 关闭 |
| `UPSTREAM_TIMEOUT_MS` | `60000` | 单次上游请求超时 |

### 换聊天模型

`CHAT_*` 改成任意 OpenAI 兼容的 `/chat/completions` 端点即可，**客户端不用动**。

| 提供商 | `CHAT_BASE_URL` | 常用模型 |
| --- | --- | --- |
| DeepSeek（默认） | `https://api.deepseek.com/v1` | `deepseek-flash` |
| 阿里百炼 | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen3.7-flash` / `qwen3.7-plus` |
| 智谱 BigModel | `https://open.bigmodel.cn/api/paas/v4` | `glm-*` |
| 硅基流动 | `https://api.siliconflow.cn/v1` | — |

百炼的 base URL 与嵌入段**是同一个**，所以一把百炼 Key 可以同时填 `CHAT_API_KEY`
和 `EMBEDDING_API_KEY` —— 这是唯一能"一把钥匙开两把锁"的组合（DeepSeek 没有
embedding 接口，所以这两把密钥并非天生来自同一家）。

⚠️ **思考模式：两家上游都默认开着**，这是本工程最贵的一个默认值。它在这里是纯负担，
四个理由（都不是理论，是接口文档和实测数字）：

1. 思考 token 按**输出价**计费。同一道题，qwen3.7-flash 开着思考产出 **216** 个输出 token，
   关掉后是 **1** 个。
2. **App 不显示思考过程**（客户端只取 `delta.content`，`reasoning_content` 被静默跳过），
   所以思考期间用户看到的是一个**长时间不动的空白气泡**。同一道题实测
   **3218 ms → 456 ms**；更复杂的问答上差距只会更大。
3. 思考长到吃掉 `max_tokens` 时，上游返回的是 **200 + 空正文**（`finish_reason: length`）。
   用户看到的现象是「AI 回了一条空的」。探测脚本自己就踩过：`max_tokens=8` 时，
   8 个 token 全用在推理上，正文一个字都没有。
4. 思考模式下 `temperature`、`presence_penalty`、`frequency_penalty` **全部失效**
   （官方文档原话：不报错，但也不起作用）。服务端是会转发这几个字段的 —— 也就是说
   开着思考时，客户端设的温度是白设的。

**所以设 `CHAT_ENABLE_THINKING=false`**（`.env.example` 的默认值已经是它）。

两家对同一件事的**写法不同**，而且都**静默忽略**对方那个（实测，谁都不报错），
所以服务端**两个一起发**，各家各自认领自己认识的那个：

| 上游 | 关掉思考的字段 |
| --- | --- |
| Qwen / DashScope | `enable_thinking: false` |
| DeepSeek | `thinking: { type: 'disabled' }` |

曾有一版只发 `enable_thinking`，在 DeepSeek 上**看着像生效、实际是空操作**：日志和 `/health`
都显示 `off`，模型照旧思考（实测该参数下推理 token 仍是 38）。同时发两种写法就是为了消掉
这类静默失效 —— 按 base URL 或模型名分支也能工作，但那会在换供应商时**悄悄**退化。

⚠️ **`/health` 回答的是「发了什么」，不是「模型做了什么」。** 要确认开关真的生效，只能看一次
真实调用的 `usage`：

```bash
npm run check-upstream     # 打印这次请求的推理 token 数，0 才是真关掉了
```

反过来说，如果某家供应商两种写法都不认，就把它设成**留空**：服务端一个字段都不发 ——
未知参数**可能被拒收**而不是被忽略，所以「不干预」始终保留为一个可用选项。

这两个字段都**只由服务端设置**，不在客户端转发白名单里：它们是厂商方言而非 OpenAI 字段，
且关闭它等于改变一次请求的花费 —— 和服务端覆盖 `model` 是同一类决定。

### 换嵌入模型

`EMBEDDING_*` 三项改成任意 OpenAI 兼容的 `/embeddings` 端点即可，**客户端不用动**——
App 发出的 `model` 是空串，选哪个模型属于运维方的事。

| 提供商 | `EMBEDDING_BASE_URL` | 常用模型 | 原生维度 | 单次条数 |
| --- | --- | --- | --- | --- |
| 阿里百炼（默认） | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `text-embedding-v4` / `v3` | 1024（v4 可 64~2048） | 10 |
| 智谱 BigModel | `https://open.bigmodel.cn/api/paas/v4` | `embedding-3` / `embedding-2` | 2048 / 1024 | — |
| 硅基流动 | `https://api.siliconflow.cn/v1` | `BAAI/bge-m3` | 1024（固定） | — |
| 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` | `doubao-embedding-*` | 1024 | — |
| OpenAI | `https://api.openai.com/v1` | `text-embedding-3-small` / `large` | 1536 / 3072 | — |
| 自建 Ollama | `http://<host>:11434/v1` | `bge-m3` | 1024 | — |

注意 base URL 的**根路径不是统一的**：智谱是 `/api/paas/v4`（不是 `/v1`），火山是 `/api/v3`。
服务端在它后面拼 `/embeddings`。

三个会咬人的点：

1. **换模型 = 重建索引，不是改配置而已。** 向量空间不可比，新旧向量混用时检索会返回
   "自信的错误答案"。离线预算的那 241 块向量必须与运行时 query 用**同一个**模型。
2. **`EMBEDDING_DIMENSION` 身兼两职**：非 0 时既作为请求参数 `dimensions` 发给上游，
   也用于校验响应宽度。而 `BAAI/bge-m3` **会拒绝 `dimensions` 参数** —— 用它就得保持
   `EMBEDDING_DIMENSION=0`，代价是失去那层宽度校验。反过来，MRL 模型
   （`text-embedding-v4`、`Qwen3-Embedding`）可以主动设小维度，省的是随包发布的存储。
3. **不需要密钥的自建服务要填占位值。** `configured()` 要求 base 与 key 都非空，
   所以 Ollama 这类不鉴权的端点必须写个假的（如 `EMBEDDING_API_KEY=ollama`），
   否则 `/embed` 永远回 503——现象看起来像服务挂了，实际是配置判定。

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

⚠️ Base URL **只填到域名**（可含反向代理的路径前缀），例如 `https://ai.example.edu`。
不要填成 `https://ai.example.edu/embed` 或 `/v1/chat/completions` —— App 会自己拼路径。

面板里有一个 **「测试连接」** 按钮，点一下就能知道配置对不对，不必发消息试错。
它测的是**当前输入框里的值**（不是已保存的），并分两步回答两个问题：

1. `GET /health` —— 证明地址对、并报出服务端配置了哪些能力；
2. 一次**故意不带合法请求体**的 POST —— 服务端在入参校验之前先查鉴权，
   所以「401 = 令牌不对」与「其它 = 令牌可用」能干净分开，且**不会真的调用模型、不花钱**。

结果直接给结论：`连接正常` / `连不上后端` / `路径不对` / `令牌被拒` / `缺少令牌` /
`后端出错`，每条都附一句该改什么。

## 测试

```bash
cd server
node --test        # 161 个用例
```

| 文件 | 用例 | 覆盖 |
| --- | --- | --- |
| `test/units.test.js` | 48 | 配置解析、令牌比较、嵌入分批与校验、聊天白名单、上游状态码映射 |
| `test/api.test.js` | 38 | 端到端：真起服务 + 桩上游，走真实的鉴权 / 路由 / 中转 / 审计 |
| `test/smoke.test.js` | 51 | 自检脚本本身（注入 fetch，逐个制造失败分支） |
| `test/smoke-e2e.test.js` | 9 | 自检脚本跑在**真实 HTTP 服务器**上 |
| `test/deploy.test.js` | 15 | 部署产物结构护栏（Dockerfile / compose / 反代 / systemd） |

`node --test` 不带路径参数（带目录会被当成文件，报 `MODULE_NOT_FOUND`）。

两处刻意的设计：

- **自检脚本有测试**。它的输出会被当成「线上是好的」的依据，一个自己会误报通过的自检
  比没有自检更糟。开发过程中它确实抓到过两次自身的误报（只数 `data:` 导致空流被判通过、
  鉴权关闭时全部跳过导致断链被判全绿）。
- **部署产物有护栏**。Dockerfile / compose / 反代配置一行都不会被业务测试碰到，
  却最容易被顺手改坏。`deploy.test.js` 断言 `cap_drop: ALL`、`read_only`、
  `flush_interval -1`、`proxy_buffering off`、`NoNewPrivileges` 这些项仍在——
  **这 7 条已做过变异验证**（故意删掉它们，测试确实会红）。

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

本服务**不读 `.env` 自身**——环境变量由你喂进来（compose 的 `env_file` 或 systemd 的
`EnvironmentFile`）。这样「密钥从哪来」这件事只有一个地方需要管。

仓库里已备好四套产物：

```
Dockerfile                      node:22-alpine，非 root，自带 /health 探活，零 RUN
docker-compose.yml              api（只绑回环）+ 可选 caddy（自动 HTTPS）
.dockerignore                   确保 .env 与测试不进构建上下文
deploy/Caddyfile                自动 TLS；已设 flush_interval -1
deploy/nginx.conf.example       已有 nginx 时抄这里；已设三行 SSE 必需项
deploy/safeta-ai-backend.service 裸机 systemd；EnvironmentFile + 沙箱加固
scripts/gen-token.mjs           生成 APP_TOKEN（只打印，不写文件）
scripts/check-upstream.mjs      起服务前的凭据体检（见上）
scripts/smoke.mjs               部署后自检（见下）
scripts/serve.ps1               Windows 运行器：载入 .env、定位 node、日志落盘
scripts/manage-autostart.ps1    Windows 开机自启（任务计划，见方式四）
```

### 方式一：Docker Compose（推荐）

```bash
cd server
cp .env.example .env
node scripts/gen-token.mjs          # 把输出的 APP_TOKEN=... 粘进 .env
$EDITOR .env                        # 填 CHAT_API_KEY / EMBEDDING_API_KEY
chmod 600 .env

docker compose up -d                # 只起后端（前面已有自己的反代时）
docker compose --profile tls up -d  # 连 Caddy 一起起，自动申请 TLS 证书
```

用 `--profile tls` 时先在 shell 或 `server/.env` 里设 `API_DOMAIN`（要真的解析到本机）
和 `ACME_EMAIL`。证书状态存在 `caddy_data` 卷里，**不要删**——否则每次重建都重新申请，
会撞 Let's Encrypt 的频率限制。

`api` 默认只绑 `127.0.0.1:8787`，对外一律经反代。这不是可选项：一个能用你模型额度的
代理裸露在公网上，被扫到只是时间问题。

### 方式二：裸机 systemd

`deploy/safeta-ai-backend.service` 顶部有完整安装步骤。核心是密钥文件的属主与权限：

```bash
sudo cp server/.env.example /etc/safeta-ai-backend.env
sudo chown root:root /etc/safeta-ai-backend.env
sudo chmod 600 /etc/safeta-ai-backend.env     # ← 这一步不能省
sudo systemctl enable --now safeta-ai-backend
journalctl -u safeta-ai-backend -f
```

systemd 以 root 身份在**降权之前**读完这个文件，所以进程仍以 `safeta` 用户运行，
而密钥文件对任何非 root 都不可读。

### 方式三：只在本机验证

```bash
cd server
PORT=8787 APP_TOKEN=$(node scripts/gen-token.mjs --quiet) \
CHAT_API_KEY=sk-xxx EMBEDDING_API_KEY=sk-yyy \
node src/index.js
```

### 方式四：Windows 开机自启（任务计划程序）

开发机上想「重启后不用再开一个命令行窗口」，用这两条：

```powershell
cd server
powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Install   # 安装
powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Start     # 立即跑一次
powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Status    # 看状态
```

`-Action` 还接受 `Stop` / `Uninstall`（卸载只删任务，日志保留）。

**为什么不用 NSSM / WinSW**：本服务刻意零依赖——持有厂商密钥的组件不引入任何供应链风险。
`schtasks` 是系统自带的，不新增任何东西。

有三个设置是刻意的，改坏了不会报错、只会静默出事：

| 设置 | 值 | 不这么做会怎样 |
|---|---|---|
| 触发时机 | 登录后 **30 秒** | 服务一起来就要出网连厂商，太早可能还没网 |
| `ExecutionTimeLimit` | **无限** | 任务计划默认 3 天，服务会在第 4 天**静默死掉** |
| `MultipleInstances` | `IgnoreNew` | 重复登录 / RDP 重连会起第二份 |

### 看门狗：为什么登录触发还不够

登录触发只保证「登录时启动过一次」，不保证「一直活着」。2026-09-19 实测过一次：
服务被中断（退出码 `0xC000013A`）后**没有自愈** —— 任务状态回到 `Ready`、端口无人监听，
而上面那个 `RestartOnFailure`（3 次 / 1 分钟）完全没起作用：**它管的是"启动失败"，
管不了"起来几小时之后进程死掉"。** 只靠登录触发，服务要等到下次登录才回来。

所以任务挂**两个**触发器，动作本身按周期重复，让任务成为它自己的看门狗：

| 触发器 | 作用 |
|---|---|
| 登录触发（延迟 30 秒） | 登录时启动 |
| 时间触发 + `Repetition.Interval` | 每 **5 分钟**重跑一次同一动作（`-WatchdogMinutes` 可调） |

它敢每个周期无脑重跑，是因为 `serve.ps1` 幂等：端口已被占用时打一行
`nothing to do` 就退出。所以服务健康时一个周期只花一次 PowerShell 启动，
服务死了则最多一个周期后自己回来（实测 43 秒）。

两个坑（都是实测踩出来的，不是推测）：

- **重复必须挂在独立触发器上。** 把 `Repetition` 挂到*登录*触发器上会注册得很成功、
  `Repetition.Interval` 读回来也确实是 `PT1M`，然后**永远不触发** —— 登录触发器的重复窗口
  锚定在登录事件上，而"任务安装之前就已经登录"的会话里那个事件不会再来。装了等于没装。
- **不要给 `-RepetitionDuration`。** 省略它才是"无限重复"；想当然地传
  `[TimeSpan]::MaxValue` 会被任务计划拒收（`任务 XML 包含格式不正确或超出范围的值 … Duration:P99999999DT23H59M59S`），
  而且 `Register-ScheduledTask` 把失败报成**非终止错误**，脚本会继续跑下去打印"已安装"。
  安装完必须把任务读回来确认。

`serve.ps1` 是任务计划实际调用的运行器，它做三件事：把 `.env` 喂成进程环境变量
（服务端本身刻意不读 `.env`——这就是 systemd `EnvironmentFile` 在 Windows 上的对等物）、
自动定位 `node.exe`（托管运行时在带版本号的目录里，写死路径会在升级后静默失效）、
把 stdout/stderr 追加进 `server/logs/backend.log`（超过 5 MB 自动滚动为 `.1`）。

`serve.ps1` 也可以手工跑，等价于方式三：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\serve.ps1
```

**想「开机即启、无需登录」**：要把触发改成 AtStartup 并让任务以 SYSTEM 运行，
或勾「不管用户是否登录都运行」+ 保存账户密码。两条路都比现在多一份权限，开发机上不值得。
真要当常驻服务器用，请走上面的 Docker 或 systemd。

排查：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\manage-autostart.ps1 -Action Status
Get-Content server\logs\backend.log -Tail 20
```

> 任务的 `State=Running` **不等于** node 活着（它只说明那个 powershell 进程还在）。
> `-Action Status` 会同时探一次端口，两个都看才作数。
> 日志开头三行写明了它选了哪个 node、载入了几个键、监听哪个端口——出问题先看这三行。
>
> `-Action Status` 最后还会打印**当前该填进 App 的那一行地址**（取默认路由所在网卡，
> 避开 VirtualBox 之类没有默认路由的虚拟网卡）。局域网 IP 会随 DHCP 变化，手机侧
> 「连不上后端」十有八九只是 App 里那一串过期了 —— 以这段输出为准，别照抄以前记下的。

### 部署后必做：自检

```bash
node scripts/smoke.mjs --base https://api.example.com --token <同一把 APP_TOKEN>
```

它把「线上这一份到底通不通」变成一条命令，覆盖你关心的三种情形：

| 情形 | 自检该给出什么 |
| --- | --- |
| 一切正常 | 全 PASS（未配密钥的能力会是 WARN + SKIP，不是 FAIL） |
| 令牌填错 | 功能检查 FAIL，文案直说「令牌被拒」并提示核对首尾空格 |
| 后端不可达 | 连通性 FAIL 并打印 `ECONNREFUSED` / `ENOTFOUND`，外加一份排查顺序 |

另外它会**扫响应体**：出现厂商密钥特征（`sk-...`）或上游主机名一律判 FAIL——
`/health` 和错误体是最容易被无意间带出这些信息的地方。

退出码：`0` 通过（WARN 不算失败）、`1` 有 FAIL、`2` 用法错误。可直接接进 CI 或发布脚本。
令牌从不被打印，只输出长度与指纹。

### 部署后注意（两条容易踩的）

1. **反代必须关响应缓冲**。Caddy 用 `flush_interval -1`，nginx 用 `proxy_buffering off`
   + `X-Accel-Buffering no`。少了任一条，App 侧的流式回答会退化成「转圈很久、
   然后整段蹦出来」——功能看着没坏，体验全毁，而且很难查出原因。
2. **限流在反代之后会变成全局的**。服务端刻意**不读 `X-Forwarded-For`**（那个头谁都能伪造），
   按 socket 地址限流；走了反代之后所有 App 都是同一个地址，于是
   `RATE_LIMIT_PER_MINUTE`（默认 120）实际是**全局**上限而不是每人一份。
   几个人用的演示/答辩场景够用；要真正按人限流需在反代侧加 `limit_req`，
   或给服务端加一个显式的「信任几跳反代」开关——**目前刻意没做**，这是个已知边界。

### 上线检查清单

**部署前**——跑 `npm run check-upstream`，零 FAIL 才动手：

- [ ] 键名与 `.env.example` 一致，没有拼错的键（写错的键会被静默忽略）
- [ ] 聊天侧与嵌入侧都通过了真实请求
- [ ] 聊天那条显示的是「真的能出话（含余额）」——只到「密钥有效」还不够，那是余额还没验

**部署后**：

- [ ] `APP_TOKEN` 已设且**不是** `.env.example` 里的占位值
- [ ] `.env`（或 `/etc/safeta-ai-backend.env`）权限 600，且 `git status` 里看不到它
- [ ] `https://` 可达，HTTP 会跳转
- [ ] `GET /health` 里 `chat.configured` 与 `embedding.configured` 都是 `true`
- [ ] `/health` 的响应里没有上游地址、没有任何密钥
- [ ] `node scripts/smoke.mjs --base <URL> --token <TOKEN>` 零 FAIL
- [ ] 日志轮转已生效（compose 已配 10 MB × 5）
- [ ] 收到 `SIGINT` / `SIGTERM` 会优雅关闭（`docker compose stop` 后日志有 `shutting down`）

泄露处置：重新 `node scripts/gen-token.mjs` 换一把即可让旧客户端失效，**不需要重新发版**。

## 未做 / 边界

- **真实 embedding 尚未接进 App**。服务端已经就绪，但客户端默认仍是**纯词法 BM25**。
  这是实测结论，不是遗漏：本地哈希嵌入器与 BM25 等权融合时，Recall@3 从 0.8485
  **掉到** 0.7879 —— 没有语义能力的嵌入当等权伙伴只会挤掉正确结果。
  接上真实嵌入模型后换掉 embedder 即可，RRF 融合层不用动。
- 限流是**进程内**的。多实例部署时每个实例各算一份，需要共享存储才能全局生效。
- 没有做请求级别的用量记账 / 配额（当前只有审计行与限流）。
