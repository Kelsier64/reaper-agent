#!/usr/bin/env node
// tools/reaper.mjs - one CLI for agents (Claude Code, Codex, ...) that have a shell.
// Wraps tools/*.ps1, which stay the single source of truth (lock, timeouts, heartbeat checks).
//
//   node tools/reaper.mjs status | start [--project p.rpp] | stop | restart
//   node tools/reaper.mjs exec <file.lua> [--label "add drums"] [--readonly] [--timeout 120]
//   node tools/reaper.mjs exec - --label x < code.lua     (stdin; saved under cmds/cli/ for history)
//   node tools/reaper.mjs dump [--notes] [--sends]
//   node tools/reaper.mjs render <name> [--start-bar N] [--end-bar N] [--tail S]
//   node tools/reaper.mjs analyze <file.wav>
// Global: --out <file> writes the full output there and prints only {"ok","out","bytes"}
//         (use it for big dumps so they do not flood your context).
// Prints the JSON reply of the bridge. Exit codes are those of send.ps1 / bridge.ps1
// (0 ok, 1 usage, 2 bridge not running/blocked, 3 timeout, 4 request error, 5 lock busy).
import { execFile } from 'node:child_process';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';

export const VERSION = '1.0.0';
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TOOLS = join(ROOT, 'tools');

const USAGE = `usage: node tools/reaper.mjs <command> [options]
  status | start [--project p.rpp] | stop | restart
  exec <file.lua|-> [--label text] [--readonly] [--timeout sec]
  dump [--notes] [--sends]
  render <name> [--start-bar N] [--end-bar N] [--tail sec]
  analyze <file.wav>
  global: --out <file>   write the output to a file, print a short summary`;

function ps(script, args, timeoutMs) {
  return new Promise((done) => {
    execFile('powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(TOOLS, script), ...args],
      { cwd: ROOT, timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024, windowsHide: true, encoding: 'utf8' },
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

// code that is not already a file (stdin, generated shortcuts) is saved for history
function saveCode(code, label) {
  const dir = process.env.REAPER_CLI_CMD_DIR || join(ROOT, 'cmds', 'cli');
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const lab = (safeLabel(label) || 'cli').replace(/[^\w㐀-鿿-]+/g, '_').slice(0, 30);
  const file = join(dir, `${stamp}_${process.pid}_${lab}.lua`);
  writeFileSync(file, String(code), 'utf8');
  return file;
}

// scratch file for generated read-only queries (not history-worthy)
function tmpCode(code) {
  const dir = join(ROOT, 'tests', 'tmp', 'cli');
  mkdirSync(dir, { recursive: true });
  const file = join(dir, `q_${process.pid}_${Date.now()}.lua`);
  writeFileSync(file, String(code), 'utf8');
  return file;
}

export function luaStr(s) { // Lua string literal (JSON's \uXXXX is not valid Lua, so escape bytes)
  return '"' + Buffer.from(String(s), 'utf8').toString('latin1').replace(/[\\"\x00-\x1f\x7f-\xff]/g,
    (c) => '\\' + c.charCodeAt(0).toString().padStart(3, '0')) + '"';
}

const FLAGS = new Set(['readonly', 'notes', 'sends']);
export function parseArgs(argv) {
  const pos = []; const opt = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const k = a.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      if (FLAGS.has(k)) opt[k] = true;
      else if (i + 1 >= argv.length) throw new Error(`missing value for ${a}`);
      else opt[k] = argv[++i];
    } else pos.push(a);
  }
  return { cmd: pos[0], pos: pos.slice(1), opt };
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
      case 'status': return ps('bridge.ps1', ['status'], 60000);
      case 'stop': return ps('bridge.ps1', ['stop'], 60000);
      case 'start': case 'restart':
        return ps('bridge.ps1', [cmd, ...(opt.project ? ['-Project', opt.project] : [])], 180000);
      case 'exec': {
        const src = pos[0];
        if (!src) return fail('exec needs a .lua file or - for stdin');
        const timeout = opt.timeout === undefined ? 120 : num(opt.timeout, '--timeout');
        let file;
        if (src === '-') {
          const code = await readStdin();
          if (!code.trim()) return fail('no code on stdin');
          file = saveCode(code, opt.label);
        } else {
          file = isAbsolute(src) ? src : resolve(process.cwd(), src);
          if (!existsSync(file)) return fail(`file not found: ${file}`);
        }
        const r = await sendFile(file, { label: opt.label, readonly: !!opt.readonly, timeout });
        return src === '-' ? { ...r, saved: file } : r;
      }
      case 'dump':
        return sendFile(tmpCode(`return H.dump({ notes = ${!!opt.notes}, sends = ${!!opt.sends} })`),
          { label: 'dump', readonly: true });
      case 'render': {
        const name = pos[0];
        if (!name || !/^[\w.-]+$/.test(name)) return fail('render needs a name: [A-Za-z0-9-_.]');
        const o = [];
        if (opt.startBar !== undefined) o.push(`start_bar = ${num(opt.startBar, '--start-bar')}`);
        if (opt.endBar !== undefined) o.push(`end_bar = ${num(opt.endBar, '--end-bar')}`);
        if (opt.tail !== undefined) o.push(`tail = ${num(opt.tail, '--tail')}`);
        return sendFile(tmpCode(`return H.render(${luaStr(name)}, { ${o.join(', ')} })`),
          { label: `render ${name}`, readonly: true, timeout: 600 });
      }
      case 'analyze': {
        if (!pos[0]) return fail('analyze needs a .wav path');
        const cands = isAbsolute(pos[0]) ? [pos[0]] : [resolve(process.cwd(), pos[0]), join(ROOT, pos[0])];
        const p = cands.find((c) => existsSync(c));
        if (!p) return fail(`file not found: ${cands.join(' or ')}`);
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
