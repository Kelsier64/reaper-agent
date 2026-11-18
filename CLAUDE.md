@AGENTS.md

## Claude Code
- Skills 在 `.claude/skills/`，是 `.agents/skills/` 的複本。要改 skill 請改 `.agents/skills/`，再跑 `node tools/sync-skills.mjs`。
- 用 Bash 工具時可以用 heredoc 從 stdin 送 Lua：`node tools/reaper.mjs exec - --label x <<'EOF' … EOF`（會自動存到 `cmds/cli/`）。用 PowerShell 工具時一律先寫檔。
- render 可能要好幾分鐘：把指令的 timeout 設到 600000 ms，或放到背景執行。
