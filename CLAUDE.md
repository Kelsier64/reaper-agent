@AGENTS.md

## Claude Code
- 如果已經安裝了使用者層級的 `reaper-bridge` / `reaper-sound-design` skill，在這個 repo 裡它們也會觸發：
  流程照 skill 走，但 CLI 改用開發版的 `node tools/reaper.mjs`，不要用 skill 資料夾裡的 `scripts/`。
- 用 Bash 工具時可以用 heredoc 從 stdin 送 Lua：`node tools/reaper.mjs exec - --label x <<'EOF' … EOF`（會自動存到 `cmds/cli/`）。用 PowerShell 工具時一律先寫檔。
- render 可能要好幾分鐘：把指令的 timeout 設到 600000 ms，或放到背景執行。
