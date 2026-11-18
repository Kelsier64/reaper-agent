#!/usr/bin/env node
// reaper.mjs - one CLI for agents (Claude Code, Codex, ...) that have a shell.
// Wraps the *.ps1 scripts next to it, which stay the single source of truth (lock, timeouts,
// heartbeat checks). Location-independent: the same file runs from the dev repo (tools/) and
// from an installed skill (scripts/); relative paths are relative to the caller's cwd.
//
//   node tools/reaper.mjs status | start [--project p.rpp] | stop | restart
//   node tools/reaper.mjs install [--force]   (point REAPER at the bridge/ folder next to this one)
//   node tools/reaper.mjs version
//   node tools/reaper.mjs exec <file.lua> [--label "add drums"] [--readonly] [--timeout 120]
//        [--project Name]     error unless REAPER's active tab is that project (file name substring)
//        [--arg k=v ...]      available in the Lua code as ARGS.k (numbers become numbers)
//   node tools/reaper.mjs exec - --label x < code.lua     (stdin; saved under <project>/cmds/cli/)
//   node tools/reaper.mjs dump [--notes] [--sends] [--project Name]
//   node tools/reaper.mjs render <name> [--start-bar N] [--end-bar N] [--tail S] [--srate 48000] [--mono] [--project Name]
//        (also refreshes the listening page next to the WAV)
//   node tools/reaper.mjs listen [--from N] [--to N] [--tracks "A,B"] [--play] [--no-loop] [--project Name]
//        (loop + cursor + zoom + track selection in REAPER, so the user can press play)
//   node tools/reaper.mjs page [dir] [--open]   listening page renders/listen.html (players + notes)
//   node tools/reaper.mjs analyze <file.wav>
// Global: --out <file> writes the full output there and prints only {"ok","out","bytes"}
//         (use it for big dumps so they do not flood your context).
// Prints the JSON reply of the bridge. Exit codes are those of send.ps1 / bridge.ps1
// (0 ok, 1 usage, 2 bridge not running/blocked, 3 timeout, 4 request error, 5 lock busy,
//  6 install refused: REAPER already uses another bridge).
import { execFile, spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, existsSync, readFileSync, readdirSync, statSync, openSync, readSync, closeSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve, isAbsolute, basename } from 'node:path';
import { fileURLToPath } from 'node:url';

export const VERSION = '1.2.0';
const HERE = dirname(fileURLToPath(import.meta.url));   // tools/ (repo) or scripts/ (skill)
// written by tools/build-skills.mjs into an installed skill; absent in the dev repo
const BUILD_FILE = join(HERE, '..', 'VERSION.json');
export function buildInfo() {
  try { return JSON.parse(readFileSync(BUILD_FILE, 'utf8')); } catch { return null; }
}

const USAGE = `usage: node <dir>/reaper.mjs <command> [options]
  status | start [--project p.rpp] | stop | restart | install [--force] | version
  exec <file.lua|-> [--label text] [--readonly] [--timeout sec] [--project Name] [--arg k=v ...]
  dump [--notes] [--sends] [--project Name]
  render <name> [--start-bar N] [--end-bar N] [--tail sec] [--srate Hz] [--mono] [--project Name]
  listen [--from N] [--to N] [--tracks "A,B"] [--play] [--no-loop] [--project Name]
  page [dir] [--open]
  analyze <file.wav>
  global: --out <file>   write the output to a file, print a short summary`;

function ps(script, args, timeoutMs) {
  return new Promise((done) => {
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(HERE, script), ...args],
      { cwd: process.cwd(), timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024, windowsHide: true, encoding: 'utf8' },
      (err, stdout, stderr) => done({
        code: err ? (typeof err.code === 'number' ? err.code : 1) : 0,
        out: (stdout || '').replace(/^﻿/, '').trim(),
        err: (stderr || '').trim(),
        killed: !!(err && err.killed),
      }));
  });
}

function safeLabel(s) {
  return String(s ?? '').replace(/["'`$\r\n\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
}

// run a Lua file through send.ps1
function sendFile(file, { label = 'cli', readonly = false, timeout = 120 } = {}) {
  const args = ['-File', file, '-Label', safeLabel(label) || 'cli', '-TimeoutSec', String(timeout)];
  if (readonly) args.push('-ReadOnly');
  return ps('send.ps1', args, (Number(timeout) + 330) * 1000);
}

// folder of the project open in REAPER (from the bridge's status file), or null
export function reaperProjectDir() {
  try {
    const st = JSON.parse(readFileSync(join(process.env.APPDATA || '', 'REAPER', 'Scripts', 'ClaudeBridge', 'status.json'), 'utf8'));
    return st.project ? dirname(st.project) : null;
  } catch { return null; }
}

// code that is not already a file (stdin) is saved for history next to the song
function saveCode(code, label) {
  const dir = process.env.REAPER_CLI_CMD_DIR || join(reaperProjectDir() || process.cwd(), 'cmds', 'cli');
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const lab = (safeLabel(label) || 'cli').replace(/[^\w㐀-鿿-]+/g, '_').slice(0, 30);
  const file = join(dir, `${stamp}_${process.pid}_${lab}.lua`);
  writeFileSync(file, String(code), 'utf8');
  return file;
}

// scratch file for generated read-only queries (not history-worthy)
function tmpCode(code) {
  const dir = join(tmpdir(), 'reaper-cli');
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `q_${process.pid}_${Date.now()}.lua`);
  writeFileSync(file, String(code), 'utf8');
  return file;
}

export function luaStr(s) { // Lua string literal (JSON's \uXXXX is not valid Lua, so escape bytes)
  return '"' + Buffer.from(String(s), 'utf8').toString('latin1').replace(/[\\"\x00-\x1f\x7f-\xff]/g,
    (c) => '\\' + c.charCodeAt(0).toString().padStart(3, '0')) + '"';
}

const FLAGS = new Set(['readonly', 'notes', 'sends', 'force', 'mono', 'play', 'noLoop', 'open']);
export function parseArgs(argv) {
  const pos = []; const opt = { arg: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      if (FLAGS.has(k)) opt[k] = true;
      else if (i + 1 >= argv.length) throw new Error(`missing value for ${a}`);
      else if (k === 'arg') opt.arg.push(argv[++i]);
      else opt[k] = argv[++i];
    } else pos.push(a);
  }
  return { cmd: pos[0], pos: pos.slice(1), opt };
}

// one-line Lua prefix (keeps the user's line numbers): project guard + ARGS table
export function prelude(opt) {
  const parts = [];
  if (opt.project) parts.push(`H.require_project(${luaStr(opt.project)});`);
  if (opt.arg && opt.arg.length) {
    const kv = opt.arg.map((p) => {
      const m = /^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/s.exec(p);
      if (!m) throw new Error(`--arg must look like name=value: ${p}`);
      const v = /^-?\d+(\.\d+)?$/.test(m[2]) ? m[2] : luaStr(m[2]);
      return `${m[1]} = ${v}`;
    });
    parts.push(`local ARGS = { ${kv.join(', ')} };`);
  }
  return parts.join(' ');
}

// ---- listening page
function wavInfo(p) {
  try {
    const fd = openSync(p, 'r'); const b = Buffer.alloc(4096); const n = readSync(fd, b, 0, 4096, 0); closeSync(fd);
    if (b.toString('ascii', 0, 4) !== 'RIFF') return null;
    let o = 12, ch, rate, bits, data;
    while (o + 8 <= n) {
      const id = b.toString('ascii', o, o + 4), sz = b.readUInt32LE(o + 4);
      if (id === 'fmt ') { ch = b.readUInt16LE(o + 10); rate = b.readUInt32LE(o + 12); bits = b.readUInt16LE(o + 22); }
      if (id === 'data') { data = sz; break; }
      o += 8 + sz + (sz & 1);
    }
    if (!rate || !data) return null;
    return { ch, rate, bits, seconds: data / (rate * ch * (bits / 8)) };
  } catch { return null; }
}
const esc = (t) => String(t).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, '0')}`;

// renders/listen.html: every WAV (newest first) with a player and its <name>.txt note
export function writePage(dir) {
  const wavs = readdirSync(dir).filter((f) => /\.wav$/i.test(f))
    .map((f) => ({ f, t: statSync(join(dir, f)).mtimeMs, info: wavInfo(join(dir, f)) }))
    .sort((a, b) => b.t - a.t);
  const items = wavs.map((w, i) => {
    const name = w.f.replace(/\.wav$/i, '');
    const notePath = join(dir, name + '.txt');
    const note = existsSync(notePath) ? readFileSync(notePath, 'utf8').trim() : '';
    const wi = w.info;
    const fmt = wi ? `${mmss(wi.seconds)} · ${wi.rate / 1000} kHz · ${wi.ch === 1 ? 'mono' : wi.ch + ' ch'} · ${wi.bits}-bit` : '';
    const when = new Date(w.t).toLocaleString('zh-TW', { hour12: false });
    return `<li class="item${i === 0 ? ' newest' : ''}">
  <div class="head"><span class="name">${esc(name)}</span>${i === 0 ? '<span class="badge">最新</span>' : ''}</div>
  <div class="meta">${esc(when)}${fmt ? ' · ' + esc(fmt) : ''}</div>
  <audio controls preload="metadata" src="${encodeURIComponent(w.f)}"></audio>
  ${note ? `<div class="note">${esc(note)}</div>` : ''}
</li>`;
  }).join('\n');
  const title = basename(dirname(resolve(dir))) || 'renders';
  const html = `<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>試聽：${esc(title)}</title>
<style>
:root { --bg:#f7f6f3; --card:#fff; --fg:#1d1d1f; --mute:#6b6b70; --line:#e3e1dc; --accent:#c2410c; }
@media (prefers-color-scheme: dark) { :root { --bg:#161617; --card:#202022; --fg:#ececee; --mute:#9a9aa0; --line:#323236; --accent:#fb923c; } }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.55 system-ui, "Microsoft JhengHei", sans-serif; }
main { max-width:760px; margin:0 auto; padding:24px 16px 48px; }
h1 { font-size:20px; margin:0 0 4px; } .sub { color:var(--mute); margin:0 0 20px; font-size:13px; }
ul { list-style:none; padding:0; margin:0; display:grid; gap:12px; }
.item { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:14px 16px; }
.item.newest { border-color:var(--accent); }
.head { display:flex; gap:8px; align-items:center; } .name { font-weight:600; word-break:break-all; }
.badge { font-size:12px; color:var(--accent); border:1px solid var(--accent); border-radius:99px; padding:0 8px; }
.meta { color:var(--mute); font-size:13px; margin:2px 0 8px; }
audio { width:100%; } .note { white-space:pre-wrap; margin-top:8px; font-size:14px; }
</style></head><body><main>
<h1>試聽：${esc(title)}</h1>
<p class="sub">最新的在最上面。播放一個會自動暫停其他的，方便 A/B 比較。每次 render 後會自動更新，重新整理即可。</p>
<ul>
${items || '<li class="item">還沒有 render 出來的檔案。</li>'}
</ul></main>
<script>
document.addEventListener('play', (e) => { document.querySelectorAll('audio').forEach((a) => { if (a !== e.target) a.pause(); }); }, true);
</script></body></html>`;
  const out = join(dir, 'listen.html');
  writeFileSync(out, html, 'utf8');
  return { page: out, files: wavs.length, newest: wavs[0]?.f ?? null };
}
function openFile(p) {
  try { spawn('explorer.exe', [p], { detached: true, stdio: 'ignore' }).unref(); return true; } catch { return false; }
}

function readStdin() {
  return new Promise((res, rej) => {
    let s = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (d) => { s += d; });
    process.stdin.on('end', () => res(s));
    process.stdin.on('error', rej);
  });
}

// installed skill: tell the agent when the running bridge is not the one this skill documents
export function withSkillCheck(r, build = buildInfo()) {
  if (!build) return r;
  let st; try { st = JSON.parse(r.out); } catch { return r; }
  const running = st.status?.helpers;
  st.skill = { built_helpers: build.helpers, running_helpers: running ?? null, built_commit: build.commit };
  if (running && running !== build.helpers) {
    st.skill.warning = `REAPER runs helpers ${running} from ${st.status?.root}, but this skill documents ${build.helpers}. ` +
      'Some H functions in references/api.md may differ; check results carefully and tell the user.';
  }
  return { ...r, out: JSON.stringify(st) };
}

const fail = (msg, code = 1) => ({ code, out: JSON.stringify({ ok: false, error: msg }) });
const num = (v, name) => {
  const n = Number(v);
  if (!Number.isFinite(n)) throw new Error(`${name} must be a number`);
  return n;
};

export async function run(argv) {
  let a;
  try { a = parseArgs(argv); } catch (e) { return fail(e.message); }
  const { cmd, pos, opt } = a;
  try {
    switch (cmd) {
      case 'status': return withSkillCheck(await ps('bridge.ps1', ['status'], 60000));
      case 'install': return ps('install.ps1', opt.force ? ['-Force'] : [], 60000);
      case 'version': return { code: 0, out: JSON.stringify({ cli: VERSION, build: buildInfo() }) };
      case 'stop': return ps('bridge.ps1', ['stop'], 60000);
      case 'start': case 'restart':
        return ps('bridge.ps1', [cmd, ...(opt.project ? ['-Project', opt.project] : [])], 180000);
      case 'exec': {
        const src = pos[0];
        if (!src) return fail('exec needs a .lua file or - for stdin');
        const timeout = opt.timeout === undefined ? 120 : num(opt.timeout, '--timeout');
        const pre = prelude(opt);
        let file, saved = null;
        if (src === '-') {
          const code = await readStdin();
          if (!code.trim()) return fail('no code on stdin');
          file = saved = saveCode(code, opt.label);
        } else {
          file = isAbsolute(src) ? src : resolve(process.cwd(), src);
          if (!existsSync(file)) return fail(`file not found: ${file}`);
        }
        if (pre) file = tmpCode(pre + ' ' + readFileSync(file, 'utf8'));
        const r = await sendFile(file, { label: opt.label, readonly: !!opt.readonly, timeout });
        return saved ? { ...r, saved } : r;
      }
      case 'dump':
        return sendFile(tmpCode(`${prelude(opt)} return H.dump({ notes = ${!!opt.notes}, sends = ${!!opt.sends} })`),
          { label: 'dump', readonly: true });
      case 'listen': {
        const o = [];
        if (opt.from !== undefined) o.push(`from_bar = ${num(opt.from, '--from')}`);
        if (opt.to !== undefined) o.push(`to_bar = ${num(opt.to, '--to')}`);
        if (opt.tracks) o.push(`tracks = { ${opt.tracks.split(',').map((t) => luaStr(t.trim())).join(', ')} }`);
        if (opt.play) o.push('play = true');
        if (opt.noLoop) o.push('loop = false');
        return sendFile(tmpCode(`${prelude(opt)} return H.listen({ ${o.join(', ')} })`), { label: 'listen', readonly: true });
      }
      case 'page': {
        const pdir = reaperProjectDir();
        const dir = pos[0] ? resolve(process.cwd(), pos[0]) : (pdir ? join(pdir, 'renders') : null);
        if (!dir || !existsSync(dir)) return fail(`no renders folder: ${dir}`);
        const pg = writePage(dir);
        const opened = opt.open ? openFile(pg.page) : false;
        return { code: 0, out: JSON.stringify({ ok: true, ...pg, opened }) };
      }
      case 'render': {
        const name = pos[0];
        if (!name || !/^[\w.-]+$/.test(name)) return fail('render needs a name: [A-Za-z0-9-_.]');
        const o = [];
        if (opt.startBar !== undefined) o.push(`start_bar = ${num(opt.startBar, '--start-bar')}`);
        if (opt.endBar !== undefined) o.push(`end_bar = ${num(opt.endBar, '--end-bar')}`);
        if (opt.tail !== undefined) o.push(`tail = ${num(opt.tail, '--tail')}`);
        if (opt.srate !== undefined) o.push(`srate = ${num(opt.srate, '--srate')}`);
        if (opt.mono) o.push('channels = 1');
        const r = await sendFile(tmpCode(`${prelude(opt)} return H.render(${luaStr(name)}, { ${o.join(', ')} })`),
          { label: `render ${name}`, readonly: true, timeout: 600 });
        // keep the listening page next to the WAV up to date
        try {
          const path = JSON.parse(r.out).result?.path;
          if (r.code === 0 && path) r.page = writePage(dirname(path)).page;
        } catch { }
        return r;
      }
      case 'analyze': {
        if (!pos[0]) return fail('analyze needs a .wav path');
        const p = isAbsolute(pos[0]) ? pos[0] : resolve(process.cwd(), pos[0]);
        if (!existsSync(p)) return fail(`file not found: ${p}`);
        return ps('analyze.ps1', [p], 300000);
      }
      case undefined: case 'help': case '-h': case '--help':
        return { code: cmd ? 0 : 1, out: USAGE };
      default:
        return fail(`unknown command: ${cmd}\n${USAGE}`);
    }
  } catch (e) {
    return fail(String(e.message || e));
  }
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  const argv = process.argv.slice(2);
  let outFile = null;
  const i = argv.indexOf('--out');
  if (i >= 0) { outFile = argv[i + 1]; argv.splice(i, 2); }
  const r = (i >= 0 && !outFile) ? fail('missing value for --out') : await run(argv);
  let text = r.out || '';
  if (r.err) text += `\n[stderr] ${r.err}`;
  if (r.killed) text += '\n[killed: timeout]';
  if (r.saved) text += `\n[code saved to ${r.saved}]`;
  if (r.page) text += `\n[listening page: ${r.page}]`;
  if (outFile) {
    const p = resolve(process.cwd(), outFile);
    mkdirSync(dirname(p), { recursive: true });
    writeFileSync(p, text + '\n', 'utf8');
    process.stdout.write(JSON.stringify({ ok: r.code === 0, exit: r.code, out: p, bytes: Buffer.byteLength(text) }) + '\n');
  } else {
    process.stdout.write(text + '\n');
  }
  process.exitCode = r.code;
}
