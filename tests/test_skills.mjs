// tests/test_skills.mjs - skills are well-formed and .claude/skills matches .agents/skills (no bridge needed)
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { SRC, drift } from '../tools/sync-skills.mjs';

let fails = 0;
const check = (name, ok, detail = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'} skills: ${name}${ok ? '' : ' -- ' + String(detail).slice(0, 400)}`);
  if (!ok) fails++;
};

const dirs = existsSync(SRC) ? readdirSync(SRC) : [];
check('skills exist', dirs.length > 0, SRC);
for (const d of dirs) {
  const f = join(SRC, d, 'SKILL.md');
  if (!existsSync(f)) { check(`${d}: has SKILL.md`, false, f); continue; }
  const txt = readFileSync(f, 'utf8');
  const fm = txt.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  const name = fm?.[1].match(/^name:\s*(.+)$/m)?.[1].trim();
  const desc = fm?.[1].match(/^description:\s*(.+)$/m)?.[1].trim();
  check(`${d}: frontmatter name matches folder`, name === d, `name=${name}`);
  check(`${d}: has a description`, !!desc && desc.length > 20 && desc.length <= 1024, `len=${desc?.length}`);
  // every repo path a skill mentions in backticks should exist
  const paths = [...txt.matchAll(/`((?:bridge|tools|tests)\/[\w./-]+\.(?:lua|md|mjs|ps1))`/g)].map((m) => m[1]);
  const missing = paths.filter((p) => !existsSync(join(SRC, '..', '..', p)));
  check(`${d}: referenced files exist`, missing.length === 0, missing.join(', '));
}
const d = drift();
check('.claude/skills in sync (run node tools/sync-skills.mjs)', d.length === 0, d.join('; '));
process.exit(fails);
