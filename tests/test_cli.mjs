// tests/test_cli.mjs - run tools/reaper.mjs as a subprocess, like an agent would (needs a running bridge)
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, mkdirSync, writeFileSync, readdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs, luaStr } from '../tools/reaper.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const CLI = join(ROOT, 'tools', 'reaper.mjs');
const TMP = join(ROOT, 'tests', 'tmp');
const CMD_DIR = join(TMP, 'cli-history');
rmSync(CMD_DIR, { recursive: true, force: true });
mkdirSync(TMP, { recursive: true });

function cli(args, { input, cwd = ROOT } = {}) {
  const r = spawnSync('node', [CLI, ...args], {
    cwd, input, encoding: 'utf8', timeout: 300000,
    env: { ...process.env, REAPER_CLI_CMD_DIR: CMD_DIR },
  });
  const out = (r.stdout || '').trim();
  let json = null;
  try { json = JSON.parse(out.split('\n')[0]); } catch { }
  return { code: r.status, out, json, err: r.stderr };
}

let fails = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} cli: ${name}${ok ? '' : ' -- ' + String(detail).slice(0, 400)}`);
  if (!ok) fails++;
};

try {
  // pure functions
  const pa = parseArgs(['render', 'x', '--start-bar', '2', '--readonly', '--out', 'f']);
  check('parseArgs', pa.cmd === 'render' && pa.pos[0] === 'x' && pa.opt.startBar === '2' && pa.opt.readonly === true && pa.opt.out === 'f', JSON.stringify(pa));
  check('luaStr escapes quotes and UTF-8', luaStr('a"測') === '"a\\034\\230\\184\\172"', luaStr('a"測'));

  const st = cli(['status']);
  check('status running', st.code === 0 && st.json?.bridge === 'running', st.out);

  // exec from a file, with Chinese text and double quotes (the PowerShell quoting trap)
  const f = join(TMP, 'cli_exec.lua');
  writeFileSync(f, 'return { s = "測試 \\"q\\"", n = H.n("A4") }', 'utf8');
  const ex = cli(['exec', f, '--label', 'cli test', '--readonly']);
  check('exec file readonly', ex.code === 0 && ex.json?.ok && ex.json.result.s === '測試 "q"' && ex.json.result.n === 69, ex.out);

  // exec relative to the caller's cwd
  const exr = cli(['exec', 'cli_exec.lua', '--readonly'], { cwd: TMP });
  check('exec path relative to cwd', exr.code === 0 && exr.json?.ok, exr.out);

  // exec from stdin, saved for history
  const sx = cli(['exec', '-', '--label', 'stdin 測試', '--readonly'], { input: 'return "from stdin 中文"' });
  check('exec stdin', sx.code === 0 && sx.json?.result === 'from stdin 中文', sx.out);
  const hist = existsSync(CMD_DIR) ? readdirSync(CMD_DIR) : [];
  check('stdin code saved to REAPER_CLI_CMD_DIR', hist.length === 1 && sx.out.includes(CMD_DIR), `${hist} / ${sx.out}`);

  const bad = cli(['exec', '-', '--readonly'], { input: 'error("boom")' });
  check('exec error -> exit 4', bad.code === 4 && bad.out.includes('boom'), `${bad.code} ${bad.out}`);

  const nf = cli(['exec', 'nope.lua']);
  check('exec missing file -> exit 1', nf.code === 1 && nf.json?.ok === false, nf.out);

  const dump = cli(['dump']);
  check('dump', dump.code === 0 && Array.isArray(dump.json?.result?.tracks), dump.out.slice(0, 300));

  const outFile = join(TMP, 'cli_dump.json');
  rmSync(outFile, { force: true });
  const dout = cli(['dump', '--out', outFile]);
  const written = existsSync(outFile) ? JSON.parse(readFileSync(outFile, 'utf8').split('\n')[0]) : null;
  check('--out writes file and prints summary', dout.code === 0 && dout.json?.ok && dout.json.bytes > 0 && Array.isArray(written?.result?.tracks), dout.out);

  const rn = cli(['render', 'bad name!']);
  check('render validates name', rn.code === 1 && rn.json?.ok === false, rn.out);

  const an = cli(['analyze', 'does_not_exist.wav']);
  check('analyze missing file -> exit 1', an.code === 1, an.out);

  const un = cli(['frobnicate']);
  check('unknown command -> exit 1 with usage', un.code === 1 && un.out.includes('usage'), un.out);

  const mv = cli(['exec', 'x.lua', '--label']);
  check('missing option value -> exit 1', mv.code === 1 && mv.out.includes('missing value'), mv.out);

  // --arg: strings (UTF-8, quotes) and numbers reach the Lua code as ARGS; line numbers are kept
  const af = join(TMP, 'cli_args.lua');
  writeFileSync(af, 'return { s = ARGS.s, n = ARGS.n + 1, t = type(ARGS.n) }\n', 'utf8');
  const ar = cli(['exec', af, '--readonly', '--arg', 's=中文 "q"', '--arg', 'n=41']);
  check('--arg strings and numbers', ar.code === 0 && ar.json?.result?.s === '中文 "q"' && ar.json.result.n === 42 && ar.json.result.t === 'number', ar.out);
  const bad2 = cli(['exec', af, '--readonly', '--arg', 'no-equals']);
  check('--arg without = -> exit 1', bad2.code === 1 && bad2.out.includes('name=value'), bad2.out);
  writeFileSync(join(TMP, 'cli_line.lua'), 'local x = 1\nerror("on line 2")\n', 'utf8');
  const ln = cli(['exec', join(TMP, 'cli_line.lua'), '--readonly', '--arg', 'a=1']);
  const base = cli(['exec', join(TMP, 'cli_line.lua'), '--readonly']);
  const lineOf = (o) => (/request:(\d+): on line 2/.exec(o) || [])[1];
  check('prelude keeps error line numbers', lineOf(ln.out) && lineOf(ln.out) === lineOf(base.out), `${lineOf(ln.out)} vs ${lineOf(base.out)}`);

  // --project: refuses when the active tab is another project (read-only dump, nothing changes)
  const pj = cli(['dump', '--project', 'NoSuchSong_xyz']);
  check('--project mismatch -> exit 4, nothing done', pj.code === 4 && pj.out.includes('require_project'), pj.out.slice(0, 300));
  const activeName = st.json?.status?.project?.split(/[\\/]/).pop().replace(/\.rpp$/i, '');
  const pok = cli(['dump', '--project', activeName || '?']);
  check('--project match -> ok', pok.code === 0 && pok.json?.ok, pok.out.slice(0, 200));

  // listen: argument errors are caught before REAPER's view is touched
  const lb = cli(['listen', '--from', '4', '--to', '2']);
  check('listen validates the range', lb.code === 4 && lb.out.includes('to_bar must be after'), lb.out.slice(0, 300));
} catch (e) {
  check('no exceptions', false, e.stack || e);
}
process.exit(fails);
