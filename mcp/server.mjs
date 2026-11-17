#!/usr/bin/env node
// mcp/server.mjs - zero-dependency MCP (stdio, JSON-RPC 2.0) server for the REAPER bridge.
// Every tool shells out to tools/*.ps1, so the PowerShell scripts stay the single source of
// truth (lock, timeouts, heartbeat checks). Registered for Claude Code in ../.mcp.json.
import { execFile } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve, isAbsolute } from 'node:path';
import { fileURLToPath } from 'node:url';
import readline from 'node:readline';

export const VERSION = '1.0.0';
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TOOLS = join(ROOT, 'tools');

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

let seq = 0;
function safeLabel(s) {
  return String(s ?? '').replace(/["'`$\r\n\\]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60);
}
async function execLua(code, { label = 'mcp', readonly = false, timeout_sec = 120 } = {}) {
  // history of executed code; tests point this elsewhere so they don't pollute cmds/mcp
  const dir = process.env.REAPER_MCP_CMD_DIR || join(ROOT, 'cmds', 'mcp');
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
  const lab = safeLabel(label) || 'mcp';
  const file = join(dir, `${stamp}_${process.pid}_${++seq}_${lab.replace(/[^\w㐀-鿿-]+/g, '_').slice(0, 30)}.lua`);
  writeFileSync(file, String(code), 'utf8');
  const args = ['-File', file, '-Label', lab, '-TimeoutSec', String(timeout_sec)];
  if (readonly) args.push('-ReadOnly');
  const r = await ps('send.ps1', args, (Number(timeout_sec) + 330) * 1000);
  return { ...r, file };
}

function luaStr(s) { // Lua string literal (JSON's \uXXXX is not valid Lua, so escape bytes)
  return '"' + Buffer.from(String(s), 'utf8').toString('latin1').replace(/[\\"\x00-\x1f\x7f-\xff]/g,
    (c) => '\\' + c.charCodeAt(0).toString().padStart(3, '0')) + '"';
}
const num = (v, d) => (v === undefined || v === null || v === '' ? d : Number(v));

const TOOL_DEFS = [
  {
    name: 'reaper_status',
    description: 'Bridge/REAPER status: bridge running|stopped|blocked|reaper-not-running, versions, open project, visible REAPER dialogs (a modal dialog blocks the bridge - ask the user to close it), lock holder. Call this first.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => ps('bridge.ps1', ['status'], 60000),
  },
  {
    name: 'reaper_start',
    description: 'Start the bridge (and REAPER if it is not running). restart=true reloads bridge.lua (helpers.lua hot-reloads by itself, no restart needed).',
    inputSchema: { type: 'object', properties: { restart: { type: 'boolean' }, project: { type: 'string', description: '.rpp to open if REAPER has to be launched' } } },
    run: async (a) => ps('bridge.ps1', [a.restart ? 'restart' : 'start', ...(a.project ? ['-Project', a.project] : [])], 180000),
  },
  {
    name: 'reaper_exec',
    description: 'Run Lua inside REAPER (ReaScript API as `reaper`, helper table `H`, `log(...)` collects messages). `return` a value to get it back as JSON. Each non-readonly call is one undo point "Claude: <label>". Use readonly=true for queries. Read reaper_api_doc before writing code. The code is saved under cmds/mcp/ for history.',
    inputSchema: {
      type: 'object', required: ['code'],
      properties: {
        code: { type: 'string', description: 'Lua source, e.g. "return H.dump()"' },
        label: { type: 'string', description: 'short description; becomes the undo point name' },
        readonly: { type: 'boolean', description: 'true = no undo point (queries)' },
        timeout_sec: { type: 'number', description: 'default 120' },
      },
    },
    run: async (a) => execLua(a.code, a),
  },
  {
    name: 'reaper_dump',
    description: 'Snapshot of the open project: tempo, time signature, tracks (volume, pan, FX, items, note counts), regions, markers. notes=true adds every MIDI note, sends=true adds sends.',
    inputSchema: { type: 'object', properties: { notes: { type: 'boolean' }, sends: { type: 'boolean' } } },
    run: async (a) => execLua(`return H.dump({ notes = ${!!a.notes}, sends = ${!!a.sends} })`, { label: 'dump', readonly: true }),
  },
  {
    name: 'reaper_render',
    description: 'Render the master mix to <project>/renders/<name>.wav (24-bit 44.1 kHz). Replaces an existing file. Follow with reaper_analyze, since you cannot hear it.',
    inputSchema: {
      type: 'object', required: ['name'],
      properties: {
        name: { type: 'string', description: 'file name without extension, [A-Za-z0-9-_.]' },
        start_bar: { type: 'number' }, end_bar: { type: 'number' }, tail: { type: 'number', description: 'seconds after end, default 2' },
      },
    },
    run: async (a) => {
      if (!/^[\w.-]+$/.test(String(a.name))) return { code: 1, out: '{"ok":false,"error":"name must be [A-Za-z0-9-_.]"}' };
      const o = [];
      if (a.start_bar !== undefined) o.push(`start_bar = ${num(a.start_bar)}`);
      if (a.end_bar !== undefined) o.push(`end_bar = ${num(a.end_bar)}`);
      if (a.tail !== undefined) o.push(`tail = ${num(a.tail)}`);
      return execLua(`return H.render(${luaStr(a.name)}, { ${o.join(', ')} })`, { label: `render ${a.name}`, readonly: true, timeout_sec: 600 });
    },
  },
  {
    name: 'reaper_analyze',
    description: 'Objective check of a WAV: peak/RMS/crest, energy per band, strongest spectral peaks, and a 3 s timeline of level, L-R balance and stereo width (side/mid).',
    inputSchema: { type: 'object', required: ['path'], properties: { path: { type: 'string', description: 'WAV path, absolute or relative to the project' } } },
    run: async (a) => {
      const p = isAbsolute(a.path) ? a.path : join(ROOT, a.path);
      if (!existsSync(p)) return { code: 1, out: `file not found: ${p}` };
      return ps('analyze.ps1', [p], 300000);
    },
  },
  {
    name: 'reaper_api_doc',
    description: 'Reference for the helper table H (bridge/API.md) plus project rules. Read before using reaper_exec.',
    inputSchema: { type: 'object', properties: {} },
    run: async () => ({ code: 0, out: readFileSync(join(ROOT, 'bridge', 'API.md'), 'utf8') }),
  },
];

export const INSTRUCTIONS =
  'Controls a running REAPER DAW. Start with reaper_status; if a dialog is open, ask the user to close it. ' +
  'Read reaper_api_doc before reaper_exec. Prefer reaper_dump before editing so you do not clobber tracks other agents own. ' +
  'Every edit is one undo point. You cannot hear audio: render, then reaper_analyze. Problems go to ISSUES.md in the project.';

async function handle(method, params) {
  switch (method) {
    case 'initialize':
      return {
        protocolVersion: params.protocolVersion || '2025-06-18',
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'reaper-bridge', version: VERSION },
        instructions: INSTRUCTIONS,
      };
    case 'ping': return {};
    case 'tools/list':
      return { tools: TOOL_DEFS.map(({ name, description, inputSchema }) => ({ name, description, inputSchema })) };
    case 'tools/call': {
      const t = TOOL_DEFS.find((d) => d.name === params.name);
      if (!t) throw Object.assign(new Error(`unknown tool: ${params.name}`), { code: -32602 });
      let r;
      try { r = await t.run(params.arguments || {}); }
      catch (e) { return { content: [{ type: 'text', text: `tool failed: ${e.message || e}` }], isError: true }; }
      let text = r.out || '';
      if (r.err) text += `\n[stderr] ${r.err}`;
      if (r.killed) text += '\n[killed: timeout]';
      if (r.file) text += `\n[code saved to ${r.file}]`;
      return { content: [{ type: 'text', text: text || '(no output)' }], isError: r.code !== 0 };
    }
    default:
      throw Object.assign(new Error(`method not found: ${method}`), { code: -32601 });
  }
}

function send(o) { process.stdout.write(JSON.stringify(o) + '\n'); }

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  const rl = readline.createInterface({ input: process.stdin });
  rl.on('line', async (line) => {
    if (!line.trim()) return;
    let msg;
    try { msg = JSON.parse(line); } catch { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'parse error' } }); return; }
    if (msg.id === undefined || msg.id === null) return; // notification
    try { send({ jsonrpc: '2.0', id: msg.id, result: await handle(msg.method, msg.params || {}) }); }
    catch (e) { send({ jsonrpc: '2.0', id: msg.id, error: { code: e.code || -32603, message: String(e.message || e) } }); }
  });
}
