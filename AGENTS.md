# reaper-agent（開發版）

AI 透過 Lua bridge 操作正在執行的 REAPER，用自然語言編曲、設計音色，使用者也會在中間手動調整。
**跟使用者溝通一律用繁體中文。**

這個資料夾是 bridge、CLI、skills 的**開發版**：持續測試、優化、修正。
給其他 session 用的是組裝好的可移植 skills（`skills/` → `node tools/build-skills.mjs --install`）。
這份檔案是所有 agent（Codex、Claude Code…）共用的開發規則；`CLAUDE.md` 只是引用這份。

## 架構
```
agent ──(node tools/reaper.mjs …)──> tools/send.ps1 ──> %APPDATA%\REAPER\Scripts\ClaudeBridge\inbox\request.lua
                                        │  (lock 檔讓多個 agent 排隊)
REAPER ── ClaudeBridge.lua（載入器）── bridge/bridge.lua ── bridge/helpers.lua（H，熱重載）
                                        └─> outbox\response.json
```
| 路徑 | 內容 |
|---|---|
| `tools/reaper.mjs` | 給 agent 用的 CLI。不依賴所在位置：在 repo 是 `tools/`，在 skill 裡是 `scripts/` |
| `tools/send.ps1` / `bridge.ps1` / `install.ps1` / `analyze.ps1` | lock、timeout、heartbeat、啟動、安裝載入器、WAV 分析。CLI 只是包裝它們 |
| `bridge/bridge.lua` | 協定、JSON、undo、heartbeat。改了要 `node tools/reaper.mjs restart` |
| `bridge/helpers.lua` | `H` 工具函式。**存檔即生效**（熱重載）；寫壞時 bridge 繼續用上一版並在 `helpers_error` 回報 |
| `bridge/API.md` | H 的完整說明（也會變成 skill 的 `references/api.md`）。**寫 Lua 之前先讀** |
| `skills/` | 可移植 skills 的原始檔（SKILL.md + references） |
| `tools/build-skills.mjs` | 把 `skills/` + `tools/` + `bridge/` 組成自帶一切的 skill 資料夾，並安裝 |
| `notes.md` / `ISSUES.md` | 目前曲子的設計與分析 / 已知問題 |

MCP server 已經移除，保留在 `mcp-backup` 分支。

## 在這個 repo 裡操作 REAPER
流程跟 `skills/reaper-bridge/SKILL.md` 一樣（先讀它），只是 CLI 用開發版：
```
node tools/reaper.mjs status
node tools/reaper.mjs dump --out tests/tmp/dump.json
node tools/reaper.mjs exec cmds/NN_name.lua --label "做了什麼"
node tools/reaper.mjs exec q.lua --readonly
node tools/reaper.mjs render <曲名>_vN --project <曲名>
node tools/reaper.mjs analyze renders/<曲名>_vN.wav
node tools/reaper.mjs listen --project <曲名> --from 10 --to 18 --tracks "Melody"
```
REAPER 可能同時開著好幾首曲子（例如其他 session 正在做的遊戲音樂），**修改指令一律加 `--project <曲名>`**。
render 後的交付方式（直接傳 WAV、`listen`）照 `skills/reaper-bridge/SKILL.md` 的「交付試聽」。使用者不需要試聽網頁，不要做。
REAPER 載入的是這個 repo 的 `bridge/`（`status.root`）。不要在這台機器上跑已安裝 skill 的 `install --force`：
那會讓 REAPER 改用 skill 裡的舊版 bridge。

## 規則
1. **先看狀態**：`status`。`blocked` = REAPER 開著對話框（看 `dialogs`），請使用者關掉，**不要 restart**。`stopped` → `start`。
2. **編輯前先 dump**，確認現況；使用者可能手動改過。不要覆蓋或刪除不是你建的軌道，除非使用者要求。
3. **指令留紀錄**：每個修改用的指令存成 `cmds/NN_簡短名稱.lua`（編號接續最大號），送出時給 `--label`（就是 undo 名稱）。從 stdin 送的程式碼會自動存到 `cmds/cli/`。查詢用 `--readonly`。
4. **改完存檔**：`H.save()`。不要做會跳出對話框的事：關閉/結束 REAPER、對沒存過的專案存檔、開新專案。真的需要時先問使用者。
5. **聽不到聲音**：每次改音色/混音後 render → analyze，把重點寫進 `notes.md`，請使用者聽。
6. **多個 agent**：lock 只保證請求不會同時執行，不會幫你處理「兩個 agent 改同一軌」的衝突。開始前在回覆裡說明你要動哪些軌；動之前重新 dump。
7. **持續改進與測試**：修改 `bridge/`、`tools/`、`tests/`、`skills/` 之後一定要跑測試（見下方）。測試失敗不可以略過或刪測試來讓它通過。
8. **回報問題**：遇到 bug、怪行為、繞過的方法，寫進 `ISSUES.md`（格式見該檔），並在回覆裡跟使用者說：發生什麼、原因、修了沒、還剩什麼風險。不要只說「完成了」。

## 開發
### 在哪裡改
- REAPER 載入的是 **main checkout** 的 `bridge/`（載入器寫死了路徑）。在 worktree 裡改 `bridge/` 不會影響正在跑的 bridge，
  在那裡跑測試測到的也是 main 的版本（hot reload 測試還會失敗）。**bridge/helpers 一律在 main checkout 改、測、commit。**
- `tools/`、`tests/`、`skills/`、文件可以在 worktree 改，但只有在 main 上合併並跑過測試才算測過。
- 只用 `node tools/reaper.mjs start|restart` 啟動 bridge；自己用 `-nonewinst` 送腳本可能會開出第二個 REAPER。

### 新增或修改 helper
1. 改 `bridge/helpers.lua`。
2. 在 `tests/test_helpers.lua` 加測試（它在暫時的專案分頁跑，不會動到曲子）。
3. 更新 `bridge/API.md`，提升 `H.version`。
4. 影響到 agent 的用法時，一起更新 `skills/`（例如 `references/examples.md`，它的每段程式碼都會被測試執行）。

### CLI
- `tools/reaper.mjs` 只是包裝 PowerShell 腳本。lock、timeout、heartbeat 的邏輯留在 PowerShell 裡，不要複製一份。
- 它必須保持**不依賴所在位置**：只找旁邊的腳本、相對路徑以呼叫者的 cwd 為準、暫存檔放系統 temp。測試會從 repo 外面執行組好的 skill 來確認。
- 改了行為就提升 `VERSION`。

### Skills
- 原始檔在 `skills/<name>/`。`scripts/`、`bridge/`、`references/api.md`、`VERSION.json` 是組裝時從 `tools/`、`bridge/` 複製進去的，**不要放在 `skills/` 裡**。
- 內容要能**直接移植**：不能提到這個 repo 的路徑、`notes.md` 之外的曲子細節、git 規則。路徑一律相對於 skill 資料夾或使用者的工作資料夾。
- 開發相關的內容放這份檔案，不要放進 skill。
- 組裝：`node tools/build-skills.mjs`（輸出到 `dist/skills/`，不進版控）。
- 安裝給其他 session：`node tools/build-skills.mjs --install`（`~/.claude/skills/`），加 `--codex` 也裝到 `~/.agents/skills/`。
- 檢查已安裝的是否過期：`node tools/build-skills.mjs --check`。**改了 `skills/`、`tools/`、`bridge/` 並 commit 之後要重新安裝**，
  其他 session 才會用到新版。

### 測試
```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Only cli,skills
```
- 套件：`analyze`、`protocol`、`helpers`、`cli`、`skills`。結果在 `tests/last-run.log`。除了 `analyze`，都需要 bridge 在跑。
- `skills` 會組裝到 `tests/tmp/`、檢查結構和版本、從 repo 外面執行組好的 CLI、在暫時的專案分頁跑 `examples.md` 的每段程式碼、
  測試 `install` 不會蓋掉別的 bridge。

## Git
- 預設分支 `main`。一個邏輯變更一個 commit；**commit 前跑測試**（只改曲子或文件時不用）。
- `renders/*.wav` 走 Git LFS（`.gitattributes`）。`Backups/`、`tests/tmp/`、`Media/`、`dist/` 不進版控。
- `.rpp` 設成不自動 merge：同一首曲子同時只能有一個人或一個 agent 改。曲子的變更要 commit 在 main 上（REAPER 開的就是 main checkout 裡的那份）。
- 不要 commit 使用者沒同意的大型音檔或 Media。
- 在 PowerShell 裡，commit 訊息先寫成 UTF-8 檔案再 `git commit -F <檔案>`（here-string 不能當 `-F -` 的 stdin）。
- `ISSUES.md` 的格式：`### [OPEN|FIXED|WORKAROUND|WONTFIX] 標題`，加日期、現象、原因、處理方式；修好時改狀態並註明是哪個測試在防止它再發生。
