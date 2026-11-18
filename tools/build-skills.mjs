#!/usr/bin/env node
// tools/build-skills.mjs - assemble the portable skills from skills/ + tools/ + bridge/.
// A built skill folder is self-contained: copy it to any machine/agent and it works.
//
//   node tools/build-skills.mjs                    build into dist/skills/
//   node tools/build-skills.mjs --install          build, then install to ~/.claude/skills/ (Claude Code)
//   node tools/build-skills.mjs --install --codex  ... and to ~/.agents/skills/ (Codex)
//   node tools/build-skills.mjs --check            are the installed copies up to date? (exit 1 if not)
//   node tools/build-skills.mjs --out <dir>        build somewhere else (tests)
// Installing only replaces folders this script created (they contain VERSION.json with
// "source": "reaper-agent"); anything else with the same name is left alone unless --force.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const SKILLS = ['reaper-bridge', 'reaper-sound-design'];
// extra files per skill: [destination inside the skill, source in the repo]
const EXTRA = {
  'reaper-bridge': [
    ['scripts/reaper.mjs', 'tools/reaper.mjs'],
    ['scripts/send.ps1', 'tools/send.ps1'],
    ['scripts/bridge.ps1', 'tools/bridge.ps1'],
    ['scripts/analyze.ps1', 'tools/analyze.ps1'],
    ['scripts/install.ps1', 'tools/install.ps1'],
    ['bridge/bridge.lua', 'bridge/bridge.lua'],
    ['bridge/helpers.lua', 'bridge/helpers.lua'],
    ['references/api.md', 'bridge/API.md'],
  ],
};
export const TARGETS = {
  claude: join(homedir(), '.claude', 'skills'),
  codex: join(homedir(), '.agents', 'skills'),
};

function files(dir) {
  if (!existsSync(dir)) return [];
  const out = [];
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) out.push(...files(p)); else out.push(p);
  }
  return out;
}
const rel = (base, f) => relative(base, f).replace(/\\/g, '/');

export function versions() {
  const h = readFileSync(join(ROOT, 'bridge', 'helpers.lua'), 'utf8').match(/^H\.version\s*=\s*"([^"]+)"/m)?.[1];
  const b = readFileSync(join(ROOT, 'bridge', 'bridge.lua'), 'utf8').match(/BRIDGE_VERSION\s*=\s*"([^"]+)"/)?.[1];
  const c = readFileSync(join(ROOT, 'tools', 'reaper.mjs'), 'utf8').match(/VERSION = '([^']+)'/)?.[1];
  let commit = null, dirty = null;
  try {
    commit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();
    dirty = execFileSync('git', ['status', '--porcelain'], { cwd: ROOT, encoding: 'utf8' }).trim() !== '';
  } catch { }
  return { helpers: h, bridge: b, cli: c, commit, dirty };
}

// build every skill into outDir/<name>; returns the list of built folders
export function build(outDir = join(ROOT, 'dist', 'skills')) {
  const v = versions();
  const built = [];
  for (const name of SKILLS) {
    const src = join(ROOT, 'skills', name);
    const dst = join(outDir, name);
    rmSync(dst, { recursive: true, force: true });
    cpSync(src, dst, { recursive: true });
    for (const [to, from] of EXTRA[name] || []) {
      mkdirSync(dirname(join(dst, to)), { recursive: true });
      cpSync(join(ROOT, from), join(dst, to));
    }
    writeFileSync(join(dst, 'VERSION.json'), JSON.stringify({ source: 'reaper-agent', skill: name, ...v }, null, 2) + '\n');
    built.push(dst);
  }
  return built;
}

// differences between two skill folders, ignoring VERSION.json (it only records where a build came from)
export function diff(a, b) {
  const fa = new Map(files(a).map((f) => [rel(a, f), f]));
  const fb = new Map(files(b).map((f) => [rel(b, f), f]));
  const d = [];
  for (const [k, f] of fa) {
    if (k === 'VERSION.json') continue;
    if (!fb.has(k)) d.push(`missing: ${k}`);
    else if (!readFileSync(f).equals(readFileSync(fb.get(k)))) d.push(`differs: ${k}`);
  }
  for (const k of fb.keys()) if (k !== 'VERSION.json' && !fa.has(k)) d.push(`extra: ${k}`);
  return d;
}

function ours(dir) {
  try { return JSON.parse(readFileSync(join(dir, 'VERSION.json'), 'utf8')).source === 'reaper-agent'; } catch { return false; }
}

export function install(builtDirs, targetRoot, { force = false } = {}) {
  const done = [];
  for (const src of builtDirs) {
    const dst = join(targetRoot, src.split(/[\\/]/).pop());
    if (existsSync(dst) && !ours(dst) && !force) {
      throw new Error(`${dst} exists and was not installed by this script; pass --force to replace it`);
    }
    rmSync(dst, { recursive: true, force: true });
    mkdirSync(targetRoot, { recursive: true });
    cpSync(src, dst, { recursive: true });
    done.push(dst);
  }
  return done;
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  const args = process.argv.slice(2);
  const has = (f) => args.includes(f);
  const oi = args.indexOf('--out');
  try {
    if (has('--check')) {
      const tmp = join(ROOT, 'tests', 'tmp', 'skills-check');
      const built = build(tmp);
      let stale = 0;
      for (const [label, root] of Object.entries(TARGETS)) {
        if (label === 'codex' && !SKILLS.some((n) => existsSync(join(root, n)))) continue;   // codex not installed
        for (const b of built) {
          const inst = join(root, b.split(/[\\/]/).pop());
          const d = existsSync(inst) ? diff(b, inst) : ['not installed'];
          console.log(`${d.length ? 'STALE' : 'ok   '} ${label}: ${inst}${d.length ? ' -- ' + d.slice(0, 5).join(', ') : ''}`);
          if (d.length) stale++;
        }
      }
      if (stale) console.log('run: node tools/build-skills.mjs --install' + (existsSync(join(TARGETS.codex, SKILLS[0])) ? ' --codex' : ''));
      process.exit(stale ? 1 : 0);
    }
    const built = build(oi >= 0 ? resolve(args[oi + 1]) : undefined);
    const v = versions();
    console.log(`built ${built.length} skill(s) (helpers ${v.helpers}, commit ${v.commit}${v.dirty ? ', uncommitted changes' : ''}):`);
    built.forEach((b) => console.log('  ' + b));
    if (has('--install')) {
      const roots = [TARGETS.claude, ...(has('--codex') ? [TARGETS.codex] : [])];
      for (const r of roots) install(built, r, { force: has('--force') }).forEach((p) => console.log('installed ' + p));
    }
  } catch (e) {
    console.error(String(e.message || e));
    process.exit(1);
  }
}
