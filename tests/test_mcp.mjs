// tests/test_mcp.mjs - spawn mcp/server.mjs and talk MCP over stdio (needs a running bridge)
import { spawn } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const CMD_DIR = join(ROOT, 'tests', 'tmp', 'mcp');
const srv = spawn('node', [join(ROOT, 'mcp', 'server.mjs')], {
  cwd: ROOT, stdio: ['pipe', 'pipe', 'inherit'], env: { ...process.env, REAPER_MCP_CMD_DIR: CMD_DIR },
});
let buf = '';
const waiting = new Map();
srv.stdout.setEncoding('utf8');
srv.stdout.on('data', (d) => {
  buf += d;
  let i;
  while ((i = buf.indexOf('\n')) >= 0) {
    const line = buf.slice(0, i); buf = buf.slice(i + 1);
    if (!line.trim()) continue;
    const m = JSON.parse(line);
    waiting.get(m.id)?.(m); waiting.delete(m.id);
  }
});
let id = 0;
const call = (method, params = {}) => new Promise((res, rej) => {
  const my = ++id;
  const t = setTimeout(() => rej(new Error(`timeout: ${method}`)), 180000);
  waiting.set(my, (m) => { clearTimeout(t); res(m); });
  srv.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: my, method, params }) + '\n');
});
const tool = async (name, args = {}) => (await call('tools/call', { name, arguments: args })).result;

let fails = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} mcp: ${name}${ok ? '' : ' -- ' + String(detail).slice(0, 400)}`);
  if (!ok) fails++;
};

try {
  const init = await call('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test', version: '0' } });
  check('initialize', init.result?.serverInfo?.name === 'reaper-bridge' && init.result.capabilities?.tools, JSON.stringify(init));
  srv.stdin.write(JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) + '\n');

  const list = await call('tools/list');
  const names = (list.result?.tools || []).map((t) => t.name).sort().join(',');
  check('tools/list', names === 'reaper_analyze,reaper_api_doc,reaper_dump,reaper_exec,reaper_render,reaper_start,reaper_status', names);

  const st = await tool('reaper_status');
  check('reaper_status running', !st.isError && JSON.parse(st.content[0].text).bridge === 'running', st.content?.[0]?.text);

  const ex = await tool('reaper_exec', { code: 'return { s = "測試", n = H.n("A4") }', label: 'mcp test', readonly: true });
  const exj = JSON.parse(ex.content[0].text.split('\n')[0]);
  check('reaper_exec readonly', !ex.isError && exj.ok && exj.result.s === '測試' && exj.result.n === 69, ex.content[0].text);
  check('exec history goes to REAPER_MCP_CMD_DIR', ex.content[0].text.includes(CMD_DIR), ex.content[0].text);

  const bad = await tool('reaper_exec', { code: 'error("boom")', readonly: true });
  check('reaper_exec error -> isError', bad.isError && bad.content[0].text.includes('boom'), bad.content[0].text);

  const dump = await tool('reaper_dump');
  const dj = JSON.parse(dump.content[0].text.split('\n')[0]);
  check('reaper_dump', !dump.isError && Array.isArray(dj.result.tracks), dump.content[0].text.slice(0, 300));

  const doc = await tool('reaper_api_doc');
  check('reaper_api_doc', !doc.isError && doc.content[0].text.includes('H.automate_display'), doc.content[0].text.slice(0, 200));

  const rn = await tool('reaper_render', { name: 'bad name!' });
  check('reaper_render validates name', rn.isError, rn.content[0].text);

  const un = await call('tools/call', { name: 'nope', arguments: {} });
  check('unknown tool -> JSON-RPC error', un.error?.code === -32602, JSON.stringify(un));

  const um = await call('does/not/exist');
  check('unknown method -> -32601', um.error?.code === -32601, JSON.stringify(um));
} catch (e) {
  check('no exceptions', false, e.stack || e);
} finally {
  srv.kill();
}
process.exit(fails);
