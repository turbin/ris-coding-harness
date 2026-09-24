#!/usr/bin/env node
// Mermaid 块结构自检 + 导出 .mmd（供 mermaid-cli 批量真实渲染）
// 用法: node mermaid-check.js <文档目录> [图块输出目录]
// 检查: 引号配平 / 括号配平 / subgraph-end 配对 / sequence alt-loop-end 配对 / 未闭合块
const fs = require('fs');
const path = require('path');

const dir = process.argv[2] || 'docs/design';
const outDir = process.argv[3];
if (outDir) fs.mkdirSync(outDir, { recursive: true });

const files = fs.readdirSync(dir).filter(f => f.endsWith('.md')).sort();
const errors = [];
let blockCount = 0;
let dumpN = 0;

for (const f of files) {
  const text = fs.readFileSync(path.join(dir, f), 'utf8');
  const lines = text.split('\n');
  let inBlock = false, start = 0, buf = [];
  const flush = () => { if (buf.length) { blockCount++; checkBlock(f, start, buf); if (outDir) dump(buf); buf = []; } };
  for (let i = 0; i < lines.length; i++) {
    const L = lines[i];
    if (!inBlock && L.trim().toLowerCase() === '```mermaid') { inBlock = true; start = i + 1; buf = []; continue; }
    if (inBlock && L.trim() === '```') { flush(); inBlock = false; continue; }
    if (inBlock) buf.push(L);
  }
  if (inBlock) errors.push(`${f}: 未闭合的 mermaid 块`);
}

function dump(buf) {
  const name = 'block-' + String(++dumpN).padStart(2, '0') + '.mmd';
  fs.writeFileSync(path.join(outDir, name), buf.join('\n'), 'utf8');
}

function checkBlock(file, start, lines) {
  const t = lines.map(l => l.replace(/\r$/, '')).filter(l => l.trim().length > 0).map(l => l.trim());
  const isSeq = /^sequenceDiagram/.test(t[0]);
  const isFlow = /^(flowchart|graph)\s/.test(t[0]);
  if (!isSeq && !isFlow) { errors.push(`${file}:${start} 未知图类型: ${t[0]}`); return; }
  t.forEach((l, li) => {
    const q = (l.match(/"/g) || []).length;
    if (q % 2 !== 0) errors.push(`${file}:${start + li} 引号不平衡: ${l}`);
    if (/\t/.test(l)) errors.push(`${file}:${start + li} 含 TAB: ${l}`);
  });
  if (isFlow) {
    t.forEach((l, li) => {
      const unq = l.replace(/"[^"]*"/g, '');
      const bal = { '[': 0, '(': 0, '{': 0 };
      for (const ch of unq) {
        if (ch === '[') bal['[']++;
        if (ch === ']') bal['[']--;
        if (ch === '(') bal['(']++;
        if (ch === ')') bal['(']--;
        if (ch === '{') bal['{']++;
        if (ch === '}') bal['{']--;
      }
      for (const k in bal) if (bal[k] !== 0) errors.push(`${file}:${start + li} 括号不平衡(${k}): ${l}`);
    });
    let sg = 0;
    t.forEach((l, li) => {
      if (/^subgraph\b/.test(l)) sg++;
      if (/^end$/.test(l)) { sg--; if (sg < 0) errors.push(`${file}:${start + li} 多余 end`); }
    });
    if (sg !== 0) errors.push(`${file}:${start} subgraph/end 不配对 (${sg})`);
  }
  if (isSeq) {
    const stack = [];
    const msgRe = /->>|-->>|->|-->|-\)|--\)/;
    t.forEach((l, li) => {
      if (/^(loop|alt|opt|rect|critical|break|par)\b/.test(l)) stack.push(l.split(/\s+/)[0]);
      if (/^else\b/.test(l) && (!stack.length || stack[stack.length - 1] !== 'alt'))
        errors.push(`${file}:${start + li} else 不在 alt/par 内: ${l}`);
      if (/^end$/.test(l)) {
        if (!stack.length) errors.push(`${file}:${start + li} 多余 end`);
        else stack.pop();
      }
      const isKw = /^(autonumber|participant|actor|loop|alt|else|opt|Note|activate|deactivate|rect|end|par|and|critical|option|break|box|sequenceDiagram)/.test(l);
      if (!isKw && !msgRe.test(l)) {
        if (/^[A-Za-z_][\w]*\s+as\s+\S/.test(l))
          errors.push(`${file}:${start + li} 疑似 participant 声明缺 participant 关键字: ${l}`);
        else
          errors.push(`${file}:${start + li} 无法识别的行: ${l}`);
      }
    });
    if (stack.length) errors.push(`${file}:${start} 未闭合块: ${stack.join(',')}`);
  }
}

console.log(`检查目录 ${dir}，文件 ${files.length} 个，mermaid 块 ${blockCount} 个`);
if (errors.length) { console.log('发现问题:\n' + errors.join('\n')); process.exitCode = 1; }
else console.log('ALL MERMAID BLOCKS PASS STRUCTURAL CHECK');

// 渲染提示（需 mermaid-cli）:
//   for f in <outDir>/*.mmd; do npx -y @mermaid-js/mermaid-cli -i "$f" -o "${f%.mmd}.svg" -q; done
