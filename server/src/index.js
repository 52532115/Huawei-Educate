/*
 * Entry point.
 *
 * Startup does one thing beyond listening: it says out loud which capabilities
 * are unconfigured. Every one of them degrades to a clean error response rather
 * than a crash, so without this the first sign of a missing key would be a
 * student seeing a failure.
 */

import { createApp } from './app.js';
import { loadConfig } from './config.js';
import { logger } from './log.js';

const config = loadConfig(process.env);
const app = createApp(config);

if (!config.authRequired()) {
  logger.warn('APP_TOKEN is not set: authentication is disabled', {
    hint: '仅限本机演示。对外提供服务前必须设置 APP_TOKEN。',
  });
}
if (!config.chatConfigured()) {
  logger.warn('chat is not configured: /chat/completions will answer 503', {
    hint: '需要 CHAT_API_KEY。',
  });
}
if (!config.embeddingConfigured()) {
  logger.warn('embeddings are not configured: /embed will answer 503', {
    hint: '需要 EMBEDDING_API_KEY。未配置时客户端会退化为纯词法检索，功能不受影响。',
  });
}

app.server.on('error', (error) => {
  logger.error('server failed', { code: error && error.code, detail: error && error.message });
  process.exitCode = 1;
});

app.server.listen(config.port, () => {
  const address = app.server.address();
  const port = address && typeof address === 'object' ? address.port : config.port;
  logger.info('listening', {
    port,
    authRequired: config.authRequired(),
    chat: config.chatConfigured(),
    embedding: config.embeddingConfigured(),
    embeddingModel: config.embeddingModel,
    embeddingBatchSize: config.embeddingBatchSize,
    rateLimitPerMinute: config.rateLimitPerMinute,
  });
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    logger.info('shutting down', { signal });
    app.server.close(() => {
      process.exit(0);
    });
  });
}
