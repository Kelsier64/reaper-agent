# reaper-agent

AI 透過 Lua bridge 操作正在執行的 REAPER，用自然語言編曲、設計音色，使用者也會在中間手動調整。
**跟使用者溝通一律用繁體中文。**

這份檔案是所有 agent（Codex、Claude Code…）共用的規則。`CLAUDE.md` 只是引用這份。

## 架構
```
agent ──(node tools/reaper.mjs …)──> tools/send.ps1 ──> %APPDATA%\REAPER\Scripts\ClaudeBridge\inbox\request.lua
                                        │  (lock 檔讓多個 agent 排隊)
REAPER ── ClaudeBridge.lua（載入器）── bridge/bridge.lua ── bridge/helpers.lua（H，熱重載）
                                        └─> outbox\response.json
```
- `tools/reaper.mjs`：給 agent 用的 CLI（status / start / restart / exec / dump / render / analyze）。
- `bridge/bridge.lua`：協定、JSON、undo、heartbeat。改了要 `node tools/reaper.mjs restart`。
- `bridge/helpers.lua`：`H` 工具函式。**存檔即生效**（熱重載）；寫壞時 bridge 會繼續用上一版並在回應的 `helpers_error` 回報。
- `bridge/API.md`：H 的完整說明。**寫 Lua 之前先讀。**
- `tools/analyze.ps1`：render 結果的客觀分析（CLI 的 `analyze` 會呼叫它）。
- `notes.md`：目前曲子的設計與每版的分析結果。`ISSUES.md`：已知問題。
- MCP server 已經移除，保留在 `mcp-backup` 分支。

## Skills（詳細流程在這裡，動手前先讀對應的 skill）
| skill | 什麼時候用 |
|---|---|
| `reaper-bridge` | 任何要讀取或修改 REAPER 專案的工作（必讀） |
| `reaper-sound-design` | 改音色、FX 參數、automation、混音，以及 render + analyze 的檢查流程 |
| `reaper-bridge-dev` | 修改 bridge、helpers、CLI、測試或 skills 本身 |

原始檔在 `.agents/skills/`（Codex 會直接讀）。`.claude/skills/` 是給 Claude Code 的複本：
**只改 `.agents/skills/`，改完跑 `node tools/sync-skills.mjs`**，測試會檢查兩邊是否一致。

## 快速參考
```
node tools/reaper.mjs status
node tools/reaper.mjs dump --out tests/tmp/dump.json
node tools/reaper.mjs exec cmds/NN_name.lua --label "做了什麼"
node tools/reaper.mjs exec q.lua --readonly
node tools/reaper.mjs render <曲名>_vN
node tools/reaper.mjs analyze renders/<曲名>_vN.wav
```

## 規則
1. **先看狀態**：`status`。`blocked` = REAPER 開著對話框（看 `dialogs`），請使用者關掉，**不要 restart**。`stopped` → `start`。
2. **編輯前先 dump**，確認現況；使用者可能手動改過。不要覆蓋或刪除不是你建的軌道，除非使用者要求。
3. **指令留紀錄**：每個修改用的指令存成 `cmds/NN_簡短名稱.lua`（編號接續最大號），送出時給 `--label`（就是 undo 名稱）。從 stdin 送的程式碼會自動存到 `cmds/cli/`。查詢用 `--readonly`。
4. **改完存檔**：`H.save()`。不要做會跳出對話框的事：關閉/結束 REAPER、對沒存過的專案存檔、開新專案。真的需要時先問使用者。
5. **聽不到聲音**：每次改音色/混音後 render → analyze，把重點寫進 `notes.md`，請使用者聽。
6. **多個 agent**：lock 只保證請求不會同時執行，不會幫你處理「兩個 agent 改同一軌」的衝突。開始前在回覆裡說明你要動哪些軌；動之前重新 dump。
7. **持續改進與測試**：修改 `bridge/`、`tools/`、`tests/`、skills 之後一定要跑
   `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`（約 1 分鐘，會在暫時的專案分頁跑，不會動到曲子）。
   測試失敗不可以略過或刪測試來讓它通過。
8. **回報問題**：遇到 bug、怪行為、繞過的方法，寫進 `ISSUES.md`（格式見該檔），並在回覆裡跟使用者說：發生什麼、原因、修了沒、還剩什麼風險。不要只說「完成了」。

## Git
- 預設分支 `main`。一個邏輯變更一個 commit；**commit 前跑測試**（只改曲子或文件時不用）。
- `renders/*.wav` 走 Git LFS（`.gitattributes`）。`Backups/`、`tests/tmp/`、`Media/` 不進版控。
- `.rpp` 設成不自動 merge：同一首曲子同時只能有一個人或一個 agent 改。曲子的變更要 commit 在 main 上（REAPER 開的就是 main checkout 裡的那份）。
- **worktree 的限制**：REAPER 載入的是 **main checkout** 的 `bridge/`（載入器寫死了路徑）。改 bridge/helpers 請在 main checkout 改、測、commit；`tools/`、`tests/`、文件可以在 worktree 改，但只有在 main 上合併後才算測過。
- 不要 commit 使用者沒同意的大型音檔或 Media。
- 在 PowerShell 裡，commit 訊息先寫成 UTF-8 檔案再 `git commit -F <檔案>`（here-string 不能當 `-F -` 的 stdin）。
