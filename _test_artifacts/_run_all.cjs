/* Ad-hoc runner: executes every offline suite and prints a one-line summary.
 * Temporary helper; not part of the suite set. */
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const NODE = process.execPath;
const dir = __dirname;

const suites = [
  ['harness', 'ai_offline_test_harness.cjs'],
  ['p0', 'ai_agent_p0_test.cjs'],
  ['p1', 'ai_agent_p1_test.cjs'],
  ['p2', 'ai_agent_p2_test.cjs'],
  ['p3', 'ai_agent_p3_test.cjs'],
  ['p3.5', 'ai_agent_p3_5_test.cjs'],
  ['p4', 'ai_agent_p4_test.cjs'],
  ['p5', 'ai_agent_p5_test.cjs'],
  ['p6', 'ai_agent_p6_test.cjs'],
  ['p7', 'ai_agent_p7_test.cjs'],
  ['p8', 'ai_agent_p8_test.cjs'],
];

let totalPass = 0;
let totalAll = 0;
let bad = 0;

for (const [name, file] of suites) {
  let out = '';
  let code = 0;
  try {
    out = execFileSync(NODE, [path.join(dir, file)], { encoding: 'utf8', cwd: path.join(dir, '..') });
  } catch (e) {
    code = e.status === undefined ? 1 : e.status;
    out = String(e.stdout || '') + String(e.stderr || '');
  }
  const last = out.trim().split(/\r?\n/).filter(Boolean).pop() || '(no output)';
  let m = last.match(/^(\d+)\/(\d+) passed$/);
  let summary = last;
  if (!m) {
    // The harness prints a JSON report instead of a one-line summary.
    try {
      const report = JSON.parse(out);
      const s = report && report.summary;
      if (s && typeof s.total === 'number') {
        m = [null, String(s.passed), String(s.total)];
        summary = `${s.passed}/${s.total} passed`;
      }
    } catch (e) {
      // Not JSON either; fall through and report the raw tail.
    }
  }
  if (m) {
    totalPass += Number(m[1]);
    totalAll += Number(m[2]);
  }
  const ok = code === 0 && m && m[1] === m[2];
  if (!ok) {
    bad++;
  }
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name.padEnd(7)} ${summary}`);
}

console.log(`\nTOTAL ${totalPass}/${totalAll} passed, failing suites: ${bad}`);
process.exit(bad > 0 ? 1 : 0);
