// tests/test_skills.mjs - the portable skills: structure, no repo leakage, the built CLI works from
// outside the repo, install.ps1 never replaces another bridge, and every example in examples.md runs.
// Needs a running bridge. The user's song is never touched (examples run in a temporary project tab).
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build, SKILLS } from '../tools/build-skills.mjs';
import { withSkillCheck } from '../tools/reaper.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TMP = join(ROOT, 'tests', 'tmp');
const BUILD = join(TMP, 'skills-build');
mkdirSync(TMP, { recursive: true });

let fails = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} skills: ${name}${ok ? '' : ' -- ' + String(detail).slice(0, 500)}`);
  if (!ok) fails++;
};
const files = (dir) => readdirSync(dir).flatMap((e) => {
  const p = join(dir, e);
  return statSync(p).isDirectory() ? files(p) : [p];
});
const run = (cmd, args, opt = {}) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', timeout: 300000, ...opt });
  const out = (r.stdout || '').replace(/^\uFEFF/, '').trim();
  let json = null; try { json = JSON.parse(out.split('\n')[0]); } catch { }
  return { code: r.status, out, json, err: r.stderr };
};

try {
  const built = build(BUILD);
  check('build produces every skill', built.length === SKILLS.length && built.every((b) => existsSync(join(b, 'SKILL.md'))), built.join(', '));
  const helpersVersion = readFileSync(join(ROOT, 'bridge', 'helpers.lua'), 'utf8').match(/^H\.version\s*=\s*"([^"]+)"/m)[1];

  for (const dir of built) {
    const name = dir.split(/[\\/]/).pop();
    const skill = readFileSync(join(dir, 'SKILL.md'), 'utf8');
    const fm = skill.match(/^---\r?\n([\s\S]*?)\r?\n---/);
    const fmName = fm?.[1].match(/^name:\s*(.+)$/m)?.[1].trim();
    const desc = fm?.[1].match(/^description:\s*(.+)$/m)?.[1].trim();
    check(`${name}: frontmatter name matches folder`, fmName === name, `name=${fmName}`);
    check(`${name}: description 50-1024 chars`, !!desc && desc.length >= 50 && desc.length <= 1024, `len=${desc?.length}`);
    check(`${name}: SKILL.md under 500 lines`, skill.split('\n').length < 500, skill.split('\n').length);

    // every bundled file a skill points at must exist (own folder, or the sibling reaper-bridge)
    const missing = [];
    for (const f of files(dir).filter((f) => f.endsWith('.md'))) {
      const txt = readFileSync(f, 'utf8');
      for (const m of txt.matchAll(/`((?:\.\.\/reaper-bridge\/)?(?:references|scripts|bridge)\/[\w.-]+\.(?:md|mjs|ps1|lua))`/g)) {
        if (!existsSync(join(dir, m[1]))) missing.push(`${relative(dir, f)} -> ${m[1]}`);
      }
    }
    check(`${name}: referenced bundled files exist`, missing.length === 0, missing.join(', '));

    // portability: docs must not depend on this repo
    const leaks = [];
    for (const f of files(dir).filter((f) => f.endsWith('.md'))) {
      const txt = readFileSync(f, 'utf8');
      for (const pat of [/tools[\\/]/, /reaper-agent/, /AGENTS\.md/, /CLAUDE\.md/, /FurElise/, /[A-Z]:\\Users/, /mcp-backup/]) {
        if (pat.test(txt)) leaks.push(`${relative(dir, f)}: ${pat}`);
      }
    }
    check(`${name}: no repo-specific paths in docs`, leaks.length === 0, leaks.join(', '));

    const ver = JSON.parse(readFileSync(join(dir, 'VERSION.json'), 'utf8'));
    check(`${name}: VERSION.json records helpers ${helpersVersion}`, ver.source === 'reaper-agent' && ver.helpers === helpersVersion, JSON.stringify(ver));
  }

  // bundled bridge/scripts are byte-identical to the repo
  const rb = join(BUILD, 'reaper-bridge');
  const same = [['scripts/reaper.mjs', 'tools/reaper.mjs'], ['scripts/send.ps1', 'tools/send.ps1'], ['bridge/helpers.lua', 'bridge/helpers.lua'], ['references/api.md', 'bridge/API.md']]
    .every(([a, b]) => readFileSync(join(rb, a)).equals(readFileSync(join(ROOT, b))));
  check('reaper-bridge bundles current scripts, bridge and API.md', same);

  // the built skill works when copied OUTSIDE the repo and called from yet another folder
  const away = mkdtempSync(join(tmpdir(), 'reaper-skill-'));
  const cwd = mkdtempSync(join(tmpdir(), 'reaper-cwd-'));
  try {
    cpSync(rb, join(away, 'reaper-bridge'), { recursive: true });
    const cli = join(away, 'reaper-bridge', 'scripts', 'reaper.mjs');
    const st = run('node', [cli, 'status'], { cwd });
    check('copied skill: status from another folder', st.code === 0 && st.json?.bridge === 'running', st.out.slice(0, 300));
    check('copied skill: status reports matching versions', st.json?.skill?.built_helpers === helpersVersion && !st.json?.skill?.warning, JSON.stringify(st.json?.skill));
    writeFileSync(join(cwd, 'q.lua'), 'return H.n("C4")', 'utf8');
    const ex = run('node', [cli, 'exec', 'q.lua', '--readonly'], { cwd });
    check('copied skill: exec a file relative to cwd', ex.code === 0 && ex.json?.result === 60, ex.out);
    const sx = run('node', [cli, 'exec', '-', '--readonly'], { cwd, input: 'return 1 + 1', env: { ...process.env, REAPER_CLI_CMD_DIR: '' } });
    check('copied skill: stdin history goes to <cwd>/cmds/cli', sx.json?.result === 2 && existsSync(join(cwd, 'cmds', 'cli')) && readdirSync(join(cwd, 'cmds', 'cli')).length === 1, sx.out);

    // install.ps1 (bundled) with a fake APPDATA: never replaces a different bridge without -Force
    const appdata = mkdtempSync(join(tmpdir(), 'reaper-appdata-'));
    const base = join(appdata, 'REAPER', 'Scripts', 'ClaudeBridge');
    const loader = join(base, 'ClaudeBridge.lua');
    const inst = (extra = []) => run('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
      join(away, 'reaper-bridge', 'scripts', 'install.ps1'), ...extra], { env: { ...process.env, APPDATA: appdata } });
    const fresh = inst();
    const skillRoot = join(away, 'reaper-bridge', 'bridge') + '\\';
    check('install: fresh install points at the skill bridge', fresh.code === 0 && readFileSync(loader, 'utf8').includes(`[[${skillRoot}]]`), fresh.out);
    const other = 'CLAUDE_BRIDGE_ROOT = [[D:\\dev\\bridge\\]]\ndofile(CLAUDE_BRIDGE_ROOT .. "bridge.lua")\n';
    writeFileSync(loader, other, 'utf8');
    const refused = inst();
    check('install: refuses to replace another bridge (exit 6)', refused.code === 6 && readFileSync(loader, 'utf8') === other && refused.json?.current_root === 'D:\\dev\\bridge\\', refused.out);
    const forced = inst(['-Force']);
    check('install: -Force replaces it', forced.code === 0 && readFileSync(loader, 'utf8').includes(`[[${skillRoot}]]`), forced.out);
    rmSync(appdata, { recursive: true, force: true });
  } finally {
    rmSync(away, { recursive: true, force: true });
    rmSync(cwd, { recursive: true, force: true });
  }

  // version mismatch warning (pure function)
  const w = withSkillCheck({ code: 0, out: JSON.stringify({ bridge: 'running', status: { helpers: '1.0.0', root: 'X' } }) }, { helpers: '2.0.0', commit: 'abc' });
  check('status warns when running helpers differ from the skill', /differ/.test(JSON.parse(w.out).skill?.warning || ''), w.out);

  // every ```lua block in examples.md runs, in order, inside a temporary project tab
  const md = readFileSync(join(rb, 'references', 'examples.md'), 'utf8');
  const blocks = [...md.matchAll(/```lua\r?\n([\s\S]*?)```/g)].map((m) => m[1]);
  cpSync(join(ROOT, 'tests', 'fixtures', 'empty.rpp'), join(TMP, 'examples.rpp'));
  const lua = `
local orig = reaper.EnumProjects(-1)
reaper.Main_OnCommand(40859, 0)
reaper.Main_openProject("noprompt:" .. [[${join(TMP, 'examples.rpp')}]])
local sandbox = reaper.EnumProjects(-1)
local out = {}
if sandbox == orig or not H.project_file():lower():find("examples.rpp", 1, true) then
  out[1] = { ok = false, err = "could not open sandbox tab" }
else
  local tr = H.add_track("Melody")
  H.fx(tr, "Surge XT")
  H.add_notes(H.midi_item(tr, 1, 2), { { "E5", 0, 0.5, 100 }, { "D#5", 0.5, 0.5, 100 } })
  local blocks = { ${blocks.map((b) => '[==[' + b + ']==]').join(',\n')} }
  for i, src in ipairs(blocks) do
    local f, cerr = load(src, "example " .. i, "t", _ENV)
    if not f then out[i] = { ok = false, err = cerr }
    else
      local ok, res = xpcall(f, debug.traceback)
      out[i] = { ok = ok, err = (not ok) and tostring(res) or nil, res = ok and res or nil }
    end
  end
  reaper.Main_SaveProject(0, false)
  if reaper.EnumProjects(-1) == sandbox then reaper.Main_OnCommand(40860, 0) end
end
reaper.SelectProjectInstance(orig)
return { results = out, back = reaper.EnumProjects(-1) == orig }
`;
  const lf = join(TMP, 'examples.run.lua');
  writeFileSync(lf, lua, 'utf8');
  const er = run('node', [join(ROOT, 'tools', 'reaper.mjs'), 'exec', lf, '--readonly', '--label', 'skill examples', '--timeout', '300'], { cwd: ROOT });
  const res = er.json?.result;
  check(`examples.md: ${blocks.length} blocks found`, blocks.length >= 6, blocks.length);
  if (!res) check('examples.md: suite ran', false, er.out);
  else {
    res.results.forEach((r, i) => {
      const first = blocks[i].split('\n').find((l) => l.trim()) || '';
      check(`examples.md block ${i + 1} runs (${first.trim().slice(0, 40)})`, r.ok, r.err);
    });
    check('examples.md: user project re-selected after sandbox', res.back === true);
    // results that must say what the example claims
    const set = res.results.find((r) => r.res && r.res.eq_freq);
    if (set) {
      check('examples.md: H.set returns the requested display values',
        /^900/.test(set.res.eq_freq) && /^-6/.test(set.res.eq_gain) && /^300/.test(set.res.attack) && set.res.mute === 'On', JSON.stringify(set.res));
    } else check('examples.md: parameter example returned values', false, JSON.stringify(res.results));
  }
} catch (e) {
  check('no exceptions', false, e.stack || e);
}
process.exit(fails);
