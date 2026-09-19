/*
 * Access guard: the app-token check and the rate limiter.
 *
 * These are the "认证、限流" halves of AI-SEC-001's recommendation; `log.js`
 * carries the audit half.
 */

import { createHash, timingSafeEqual } from 'node:crypto';
import { TOKEN_HEADER } from './config.js';

/** Above this many tracked clients, stale buckets get swept. */
const PRUNE_THRESHOLD = 2048;

/**
 * Reads the caller's app session token.
 *
 * `Authorization: Bearer …` comes first because that is what the client
 * already sends (the same header it used against the vendor), so moving chat
 * to this server required no new header convention on the device side.
 */
export function extractToken(req) {
  const raw = req.headers['authorization'];
  if (typeof raw === 'string') {
    const prefix = 'bearer ';
    if (raw.toLowerCase().startsWith(prefix)) {
      const value = raw.substring(prefix.length).trim();
      if (value.length > 0) {
        return value;
      }
    }
  }
  const headerToken = req.headers[TOKEN_HEADER];
  if (typeof headerToken === 'string' && headerToken.trim().length > 0) {
    return headerToken.trim();
  }
  return '';
}

function digest(value) {
  return createHash('sha256').update(value, 'utf8').digest();
}

/**
 * Constant-time token comparison.
 *
 * Both sides are hashed first because `timingSafeEqual` throws when the lengths
 * differ — and "the length is wrong" is itself a hint worth not handing out.
 */
export function tokenMatches(presented, expected) {
  if (typeof presented !== 'string' || typeof expected !== 'string') {
    return false;
  }
  if (presented.length === 0 || expected.length === 0) {
    return false;
  }
  return timingSafeEqual(digest(presented), digest(expected));
}

/**
 * Fixed-window limiter, in memory.
 *
 * A fixed window is coarser than a sliding one — a client can burst either side
 * of a boundary — but it is a handful of lines, has no timers, and bounds
 * runaway usage, which is the actual goal here. Per-process state is fine while
 * the server is a single instance; more instances would need a shared store.
 *
 * The key is the socket address, and `x-forwarded-for` is deliberately **not**
 * consulted: without a trusted-proxy allowlist, honouring that header lets any
 * caller bypass the limit by inventing an address. Behind a reverse proxy,
 * limit there instead.
 */
export class RateLimiter {
  constructor(perMinute, windowMs = 60000) {
    this.perMinute = perMinute;
    this.windowMs = windowMs;
    this.buckets = new Map();
  }

  check(key, now = Date.now()) {
    if (!Number.isFinite(this.perMinute) || this.perMinute <= 0) {
      return { allowed: true, remaining: -1, retryAfterSeconds: 0 };
    }
    const bucket = this.buckets.get(key);
    if (!bucket || now - bucket.windowStart >= this.windowMs) {
      this.buckets.set(key, { windowStart: now, count: 1 });
      if (this.buckets.size > PRUNE_THRESHOLD) {
        this.prune(now);
      }
      return { allowed: true, remaining: this.perMinute - 1, retryAfterSeconds: 0 };
    }
    if (bucket.count >= this.perMinute) {
      const remainingMs = bucket.windowStart + this.windowMs - now;
      return {
        allowed: false,
        remaining: 0,
        retryAfterSeconds: Math.max(1, Math.ceil(remainingMs / 1000)),
      };
    }
    bucket.count += 1;
    return { allowed: true, remaining: this.perMinute - bucket.count, retryAfterSeconds: 0 };
  }

  /** Drops windows that have already expired. */
  prune(now = Date.now()) {
    for (const [key, bucket] of this.buckets) {
      if (now - bucket.windowStart >= this.windowMs) {
        this.buckets.delete(key);
      }
    }
  }

  reset() {
    this.buckets.clear();
  }
}
