@AGENTS.md

## Claude Code
- 如果已經安裝了使用者層級的 `reaper-bridge` / `reaper-sound-design` skill，在這個 repo 裡它們也會觸發：
  流程照 skill 走，但 CLI 改用開發版的 `node tools/reaper.mjs`，不要用 skill 資料夾裡的 `scripts/`。
- Lua 一律先寫成檔案再 `exec`。heredoc 裡的 Lua 只要同時有 `{` 和引號就會被權限檢查擋掉；`exec -`（stdin）只留給極短的查詢。
- 指令寫完整路徑，不要把 CLI 存成 shell 變數（`R=...; $R`），那也會被權限檢查擋掉。
- render 可能要好幾分鐘：把指令的 timeout 設到 600000 ms，或放到背景執行。
