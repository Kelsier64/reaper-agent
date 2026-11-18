#!/usr/bin/env node
// tools/sync-skills.mjs - copy .agents/skills (source, read by Codex) to .claude/skills (read by Claude Code).
// Edit only .agents/skills, then run: node tools/sync-skills.mjs   (--check: report drift, exit 1, change nothing)
import { cpSync, existsSync, readdirSync, readFileSync, rmSync, statSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const SRC = join(ROOT, '.agents', 'skills');
export const DST = join(ROOT, '.claude', 'skills');

function files(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...files(p)); else out.push(p);
  }
  return out;
}

// list of differences between source and copy ([] = in sync)
export function drift() {
  const a = new Map(files(SRC).map((f) => [relative(SRC, f).replace(/\\/g, '/'), f]));
  const b = new Map(files(DST).map((f) => [relative(DST, f).replace(/\\/g, '/'), f]));
  const d = [];
  for (const [k, f] of a) {
    if (!b.has(k)) d.push(`missing in .claude/skills: ${k}`);
    else if (!readFileSync(f).equals(readFileSync(b.get(k)))) d.push(`differs: ${k}`);
  }
  for (const k of b.keys()) if (!a.has(k)) d.push(`extra in .claude/skills: ${k}`);
  return d;
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  if (process.argv.includes('--check')) {
    const d = drift();
    console.log(d.length ? d.join('\n') : 'in sync');
    process.exit(d.length ? 1 : 0);
  }
  rmSync(DST, { recursive: true, force: true });
  cpSync(SRC, DST, { recursive: true });
  console.log(`synced ${files(DST).length} file(s): .agents/skills -> .claude/skills`);
}
