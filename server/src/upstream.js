/*
 * The upstream (vendor) client.
 *
 * Both upstreams this server talks to — the chat model and the embedding model
 * — speak the OpenAI wire protocol, so one client covers both and a provider
 * swap is a base-URL change. That is also why the app can be pointed at this
 * server without any protocol translation: the server relays the same shape the
 * app already understood.
 *
 * This is the only place a vendor key is ever attached to a request.
 */

/** A transport-level failure: DNS, TLS, connection reset, timeout. */
export class TransportError extends Error {
  constructor(code, message, cause) {
    super(message);
    this.code = code;
    this.cause = cause;
  }
}

export const TRANSPORT_TIMEOUT = 'upstream_timeout';
export const TRANSPORT_UNREACHABLE = 'upstream_unreachable';

/**
 * Maps an upstream status onto the status this server returns to the app.
 *
 * 4xx is passed through unchanged: those are meaningful to the client (bad
 * token, bad request, too many requests) and reporting them verbatim keeps the
 * failure explainable. 5xx becomes 502, because an upstream's own 500 tells the
 * client nothing it can act on and would misattribute the fault to this server.
 */
export function statusForApp(upstreamStatus) {
  if (upstreamStatus >= 400 && upstreamStatus < 500) {
    return upstreamStatus;
  }
  return 502;
}

export function codeForStatus(status) {
  switch (status) {
    case 400:
      return 'bad_request';
    case 401:
      return 'unauthorized';
    case 402:
      return 'payment_required';
    case 403:
      return 'forbidden';
    case 404:
      return 'not_found';
    case 408:
      return 'timeout';
    case 413:
      return 'body_too_large';
    case 429:
      return 'rate_limited';
    case 502:
      return 'upstream_error';
    case 503:
      return 'unavailable';
    default:
      return 'error';
  }
}

/**
 * Merges abort signals into one, without relying on `AbortSignal.any` so the
 * server keeps working on Node 18.
 */
export function combineSignals(signals) {
  const list = [];
  for (const signal of signals) {
    if (signal) {
      list.push(signal);
    }
  }
  if (list.length === 0) {
    return undefined;
  }
  if (list.length === 1) {
    return list[0];
  }
  const controller = new AbortController();
  const abort = () => {
    for (const signal of list) {
      if (signal.aborted) {
        controller.abort(signal.reason);
        return;
      }
    }
    controller.abort();
  };
  for (const signal of list) {
    if (signal.aborted) {
      abort();
      return controller.signal;
    }
    signal.addEventListener('abort', abort, { once: true });
  }
  return controller.signal;
}

function toTransportError(error, callerSignal) {
  if (callerSignal && callerSignal.aborted) {
    return new TransportError('client_gone', '客户端已断开', error);
  }
  const name = error && error.name ? error.name : '';
  if (name === 'TimeoutError' || name === 'AbortError') {
    return new TransportError(TRANSPORT_TIMEOUT, '上游响应超时', error);
  }
  return new TransportError(TRANSPORT_UNREACHABLE, '无法连接上游服务', error);
}

export class UpstreamClient {
  constructor(options) {
    this.baseUrl = options.baseUrl;
    this.apiKey = options.apiKey;
    this.timeoutMs = options.timeoutMs;
    this.fetchImpl = options.fetchImpl || globalThis.fetch;
  }

  configured() {
    return this.baseUrl.length > 0 && this.apiKey.length > 0;
  }

  buildHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.apiKey}`,
    };
  }

  /**
   * POSTs JSON and buffers the whole answer.
   *
   * The timeout covers the entire exchange here — a buffered response that has
   * not finished arriving is not useful, so there is nothing to gain by
   * letting it run on.
   */
  async postJson(path, body, options = {}) {
    const signal = combineSignals([options.signal, AbortSignal.timeout(this.timeoutMs)]);
    let response;
    try {
      response = await this.fetchImpl(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers: this.buildHeaders(),
        body: JSON.stringify(body),
        signal,
      });
    } catch (error) {
      throw toTransportError(error, options.signal);
    }
    const text = await response.text();
    let json = null;
    if (text.length > 0) {
      try {
        json = JSON.parse(text);
      } catch (e) {
        json = null;
      }
    }
    return { status: response.status, json, text };
  }

  /**
   * POSTs JSON and returns the live response so the caller can relay the body
   * chunk by chunk.
   *
   * The timeout is armed only until the response headers arrive and is then
   * cleared: a stream is legitimately long-lived, and cutting it off on a
   * wall-clock timer would truncate answers. A stream that stalls after the
   * headers is bounded from the other side instead — the app's own read timeout
   * closes the connection, which aborts this request through `options.signal`.
   */
  async openStream(path, body, options = {}) {
    const controller = new AbortController();
    const callerSignal = options.signal;
    const forwardAbort = () => controller.abort();
    if (callerSignal) {
      if (callerSignal.aborted) {
        controller.abort();
      } else {
        callerSignal.addEventListener('abort', forwardAbort, { once: true });
      }
    }
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await this.fetchImpl(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers: this.buildHeaders(),
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (callerSignal) {
        callerSignal.removeEventListener('abort', forwardAbort);
      }
      return response;
    } catch (error) {
      clearTimeout(timer);
      if (callerSignal) {
        callerSignal.removeEventListener('abort', forwardAbort);
      }
      throw toTransportError(error, callerSignal);
    }
  }
}
