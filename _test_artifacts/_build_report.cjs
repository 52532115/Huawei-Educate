/*
 * Summarise an hvigor build log.
 *
 * Two properties of these logs have to be handled before any matching is worth
 * anything, and both have bitten this project:
 *
 *   1. the file is **UTF-16LE with a BOM** (`*>` / `Out-File` on Windows), so
 *      reading it as utf8 turns every character into a NUL-interleaved pair and
 *      every `indexOf` returns -1 — a *failed* build then reads as "0 errors";
 *   2. lines **wrap at ~100 columns**, sometimes inside a path, so
 *      `Learne` + newline + `rProfileView.ets` is how the file actually looks.
 *      Counting has to run on a newline-stripped copy.
 *
 * ANSI colour escapes are stripped for the same reason.
 *
 * Usage:
 *   node _test_artifacts/_build_report.cjs <log> [File1.ets,File2.ets,...]
 *
 * Exits non-zero when the build did not succeed, so "the report was clean" and
 * "the build passed" cannot drift apart.
 */
const fs = require('fs');

const file = process.argv[2] || '_test_artifacts/build_p8.log';
const touched = (process.argv[3] || '').split(',').map((s) => s.trim()).filter((s) => s.length > 0);

function decode(p) {
  const b = fs.readFileSync(p);
  if (b.length >= 2 && b[0] === 0xff && b[1] === 0xfe) {
    return b.toString('utf16le');
  }
  if (b.length >= 2 && b[0] === 0xfe && b[1] === 0xff) {
    return b.swap16().toString('utf16le');
  }
  return b.toString('utf8').replace(/^\uFEFF/, '');
}

const raw = decode(file).replace(/\u001b\[[0-9;]*m/g, '');
// Wrapped paths only reassemble when the breaks are removed, so every count and
// every match below runs against this flattened view.
const flat = raw.replace(/\r?\n\s*/g, '');

console.log(`log        ${file}`);
console.log(`bytes      ${fs.statSync(file).size}`);

if (touched.length > 0) {
  console.log('--- mentions of touched files ---');
  for (const f of touched) {
    let n = 0;
    let i = 0;
    while ((i = flat.indexOf(f, i)) >= 0) { n += 1; i += f.length; }
    console.log('  ' + f.padEnd(34) + n);
  }
}

const summary = flat.match(/(BUILD SUCCESSFUL|BUILD FAILED|COMPILE RESULT:)[^{]*\{[^}]*\}|BUILD (SUCCESSFUL|FAILED)[^;]*/g) || [];
const succeeded = /BUILD SUCCESSFUL/.test(flat) && !/BUILD FAILED/.test(flat);

console.log('--- outcome ---');
console.log(summary.length > 0 ? summary.map((l) => '  ' + l).join('\n') : '  (no summary line found)');

const warnCount = (flat.match(/WARN: ArkTS:WARN/g) || []).length;
console.log(`ArkTS warnings        ${warnCount}`);

// Every distinct compiler complaint, deduplicated: the same message appears
// once per affected file and once again in the tally.
const messages = raw.match(/Error Message: [^\n]*/g) || [];
const distinct = [...new Set(messages.map((m) => m.replace(/\s+/g, ' ').trim()))];
console.log(`ArkTS errors          ${distinct.length}`);
distinct.forEach((m) => console.log('  * ' + m));

const errorFiles = [...new Set(flat.match(/At File: [^ ]+\.ets:\d+:\d+/g) || [])];
console.log(`ArkTS error sites     ${errorFiles.length}`);
errorFiles.forEach((m) => console.log('    ' + m));

if (touched.length > 0) {
  // Diagnostic text also wraps, so the whole block is reassembled from `flat`
  // and split on the marker that starts each diagnostic.
  const blocks = flat.split(/(?=ERROR:\s*\d+\s+\d+\s+ArkTS|WARN: ArkTS:WARN|Error Message:)/);
  const ours = blocks.filter((b) => touched.some((f) => b.indexOf(f) >= 0));
  console.log(`diagnostics mentioning touched files   ${ours.length}`);
  ours.forEach((b) => console.log('  ! ' + b.replace(/\s+/g, ' ').slice(0, 220)));
}

console.log(succeeded ? 'RESULT: SUCCESS' : 'RESULT: FAILURE');
process.exit(succeeded ? 0 : 1);
