/*
 * 凭据指纹的唯一实现。
 *
 * 为什么要有这个文件：`check-upstream.mjs` 与 `smoke.mjs` 都要回答同一个问题 ——
 * 「你填的这一把，和我这儿的是不是同一把」。两边各写一份算法时，同一个 APP_TOKEN
 * 算出了两个不同的指纹（一个是 SHA-256 前 8 位，一个是 31 乘子的滚动哈希），
 * 于是指纹非但帮不上比对，反而会让人以为令牌被换掉了。
 *
 * 统一为 SHA-256 前 8 位十六进制：不可逆、碰撞概率可忽略，且跨脚本可比。
 * 换算法等于让历史记录里的指纹全部失效，所以这里刻意不做任何"改进"。
 */

import crypto from 'node:crypto';

/** 稳定的短指纹：用于确认「两次填的是不是同一把」，但不泄露内容。 */
export function fingerprint(value) {
  if (typeof value !== 'string' || value.length === 0) {
    return '-';
  }
  return crypto.createHash('sha256').update(value).digest('hex').substring(0, 8);
}

/**
 * 令牌指纹：额外带上长度。
 *
 * 长度是给肉眼用的 —— 「少复制了几位」是填令牌最常见的错法，而指纹本身
 * 无法回答"是不是短了"，长度可以。
 */
export function tokenFingerprint(token) {
  if (typeof token !== 'string' || token.length === 0) {
    return '(none)';
  }
  return `len=${token.length} fp=${fingerprint(token)}`;
}
