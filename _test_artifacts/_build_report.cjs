/* One-off: summarise the hvigor build log (ANSI + UTF-16/BOM safe). */
const fs = require('fs');
const file = process.argv[2] || '_test_artifacts/build_p8.log';
let s = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
s = s.replace(/\u001b\[[0-9;]*m/g, '');

const files = ['AiBackend.ets', 'AiService.ets', 'KnowledgeEmbeddingProxy.ets',
  'AiChatView.ets', 'ChatViewModel.ets', 'AiConstants.ets', 'EntryAbility.ets'];
console.log('--- mentions of touched files ---');
for (const f of files) {
  let n = 0;
  let i = 0;
  while ((i = s.indexOf(f, i)) >= 0) { n++; i += f.length; }
  console.log(f.padEnd(30), n);
}

console.log('--- outcome ---');
const summary = s.match(/(BUILD SUCCESSFUL|BUILD FAILED|COMPILE RESULT)[^\n]*/g);
console.log(summary ? summary.join('\n') : '(no summary line)');

const warnLines = s.match(/WARN: ArkTS:WARN[^\n]*/g) || [];
console.log('ArkTS warning lines:', warnLines.length);

const errLines = s.match(/ERROR: ArkTS[^\n]*|Error Message:[^\n]*/g) || [];
console.log('ArkTS error lines:', errLines.length);
errLines.forEach((l) => console.log('  ' + l));

// Only warnings that point at files we touched this session.
const joined = s.replace(/\r?\n\s*/g, '');
const parts = joined.split(/(?=\d*\s*WARN: ArkTS:WARN)/);
const ours = parts.filter((p) => /(AiBackend|AiService|KnowledgeEmbeddingProxy|ChatViewModel|AiConstants)\.ets/.test(p.slice(0, 400)));
console.log('warnings in touched .ets files:', ours.length);
ours.forEach((p) => console.log('  * ' + p.replace(/\s+/g, ' ').slice(0, 200)));
