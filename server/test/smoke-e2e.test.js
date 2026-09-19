/*
 * scripts/smoke.mjs 的端到端验证。
 *
 * smoke.test.js 用注入的 fetchImpl 覆盖每个失败分支；这里补上另一半——
 * **真起服务器、真走 socket、真的跑一遍自检脚本**。
 *
 * 两者缺一不可：注入版能制造线上难出现的坏法，但证明不了脚本会连 HTTP；
 * 这版能证明连接、SSE 分帧、状态码都成立，但制造不出「响应体回显密钥」这类坏法。
 *
 * 复用 testlib/support.js 的真实服务器 + 桩厂商，所以仍然零网络、零真实凭据。
 */

import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

import { runSmoke, summarize, tokenFingerprint } from '../scripts/smoke.mjs';
import { APP_TOKEN, startApp, startStubUpstream } from '../testlib/support.js';

function optionsFor(origin, token = APP_TOKEN, extra = {}) {
  return Object.assign({
    base: origin,
    token,
    runChat: true,
    runEmbed: true,
    timeoutMs: 10000,
  }, extra);
}

function statusOf(report, name) {
  const found = report.results.find((r) => r.name === name);
  return found ? found.status : '(missing)';
}

function detailOf(report, name) {
  const found = report.results.find((r) => r.name === name);
  return found ? found.detail : '';
}

/** 占一个端口再放掉，得到一个大概率没人监听的地址。 */
async function findDeadPort() {
  const probe = createServer();
  const port = await new Promise((resolve) => {
    probe.listen(0, '127.0.0.1', () => {
      resolve(probe.address().port);
    });
  });
  await new Promise((resolve) => {
    probe.close(() => {
      resolve();
    });
  });
  return port;
}

test('真实部署下的正常路径：全 PASS，无失败无警告无跳过', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    const report = await runSmoke(optionsFor(app.origin), fetch);
    const counts = summarize(report.results);
    assert.equal(counts.FAIL, 0, JSON.stringify(report.results));
    assert.equal(counts.WARN, 0, JSON.stringify(report.results));
    assert.equal(counts.SKIP, 0, JSON.stringify(report.results));
    assert.equal(report.authRequired, true);
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('真实部署下自检能识别出流式确实在流', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    const report = await runSmoke(optionsFor(app.origin), fetch);
    assert.equal(statusOf(report, '聊天流式'), 'PASS');
    // 桩上游发 3 个内容分片 + 1 个终结符；自检只该数到 3。
    assert.ok(detailOf(report, '聊天流式').indexOf('SSE 3 片') >= 0,
      detailOf(report, '聊天流式'));
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('真实部署下嵌入条数与宽度都对得上', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    const report = await runSmoke(optionsFor(app.origin), fetch);
    assert.equal(statusOf(report, '嵌入返回一致'), 'PASS');
    assert.ok(detailOf(report, '嵌入返回一致').indexOf('宽度 8') >= 0,
      detailOf(report, '嵌入返回一致'));
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('真实部署下错令牌被拒，且错误体不泄露上游地址', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    const report = await runSmoke(optionsFor(app.origin, 'wrong-token'), fetch);
    // 令牌错 → /health 仍可读（不带鉴权），但所有带鉴权的检查都会 401。
    assert.equal(statusOf(report, '健康检查'), 'PASS');
    assert.equal(statusOf(report, '错误令牌被拒'), 'PASS');
    // 401 的响应体不该带出上游主机名。
    assert.equal(statusOf(report, '响应体无上游地址'), 'PASS');
    // 带错令牌时嵌入检查会拿到 401，因此判 FAIL——这是正确行为：
    // 令牌不匹配时部署不可用，自检必须红。
    assert.equal(statusOf(report, '嵌入返回一致'), 'FAIL');
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('真实部署下未配密钥：报 WARN 与 SKIP，不报 FAIL', async () => {
  const app = await startApp();
  try {
    const report = await runSmoke(optionsFor(app.origin), fetch);
    const counts = summarize(report.results);
    assert.equal(counts.FAIL, 0, JSON.stringify(report.results));
    assert.equal(statusOf(report, '聊天已配置'), 'WARN');
    assert.equal(statusOf(report, '嵌入已配置'), 'WARN');
    assert.equal(statusOf(report, '嵌入返回一致'), 'SKIP');
    assert.equal(statusOf(report, '聊天非流式'), 'SKIP');
    assert.equal(statusOf(report, '健康检查'), 'PASS');
    assert.equal(statusOf(report, '匿名访问被拒'), 'PASS');
  } finally {
    await app.close();
  }
});

test('真实部署下关闭鉴权会被明确警告', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream, appToken: '' });
  try {
    const report = await runSmoke(optionsFor(app.origin, ''), fetch);
    assert.equal(report.authRequired, false);
    assert.equal(statusOf(report, '匿名访问被拒'), 'WARN');
    assert.ok(detailOf(report, '匿名访问被拒').indexOf('危险的') >= 0);
    // 鉴权关掉也不该影响功能可用性。
    assert.equal(statusOf(report, '聊天非流式'), 'PASS');
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('端口无人监听时给出连通性 FAIL，而不是抛异常', async () => {
  const port = await findDeadPort();
  const report = await runSmoke(optionsFor(`http://127.0.0.1:${port}`), fetch);
  assert.equal(statusOf(report, '连通性'), 'FAIL');
  assert.equal(statusOf(report, '健康检查'), 'SKIP');
  assert.equal(report.results.length, 2);
});

test('自检报告里不会出现真实令牌', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    const report = await runSmoke(optionsFor(app.origin), fetch);
    const serialized = JSON.stringify(report.results);
    assert.ok(serialized.indexOf(APP_TOKEN) < 0, '报告里不能带令牌');
    assert.ok(tokenFingerprint(report.token).indexOf(APP_TOKEN) < 0);
  } finally {
    await app.close();
    await upstream.close();
  }
});

test('自检不会把上游密钥带进任何请求', async () => {
  const upstream = await startStubUpstream();
  const app = await startApp({ upstream });
  try {
    await runSmoke(optionsFor(app.origin), fetch);
    // 自检只打自家服务；桩上游收到的请求应全部来自服务端转发，
    // 且 Authorization 用的是服务端自己配的桩密钥，不是自检脚本的东西。
    for (const request of upstream.state.requests) {
      const header = request.headers.authorization || '';
      assert.ok(header.indexOf(APP_TOKEN) < 0, '应用令牌绝不能出现在发往厂商的请求里');
    }
  } finally {
    await app.close();
    await upstream.close();
  }
});
