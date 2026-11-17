# reaper-agent

AI 透過 Lua bridge 操作正在執行的 REAPER，用自然語言編曲、設計音色，使用者也會在中間手動調整。
**跟使用者溝通一律用繁體中文。**

## 架構
```
agent ──(MCP: mcp/server.mjs)──┐
agent ──(tools/send.ps1)───────┴─> %APPDATA%\REAPER\Scripts\ClaudeBridge\inbox\request.lua
                                    │  (lock 檔讓多個 agent 排隊)
REAPER ── ClaudeBridge.lua（載入器）── bridge/bridge.lua ── bridge/helpers.lua（H，熱重載）
                                    └─> outbox\response.json
```
- `bridge/bridge.lua`：協定、JSON、undo、heartbeat。改了要 `tools\bridge.ps1 restart`。
- `bridge/helpers.lua`：`H` 工具函式。**存檔即生效**（熱重載）；寫壞時 bridge 會繼續用上一版並在回應的 `helpers_error` 回報。
- `bridge/API.md`：H 的完整說明。**寫 Lua 之前先讀。**
- `tools/analyze.ps1`：render 結果的客觀分析（峰值/RMS、頻段、頻譜峰、3 秒時間軸的音量/左右平衡/寬度）。
- `notes.md`：目前曲子的設計與每版的分析結果。`ISSUES.md`：已知問題。

## 操作方式（二選一）
**MCP**（此資料夾的 `.mcp.json` 註冊了 `reaper` server，第一次使用需要使用者核准）：
`reaper_status` → `reaper_api_doc` → `reaper_dump` → `reaper_exec` / `reaper_render` / `reaper_analyze`

**PowerShell**：
```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\bridge.ps1 status
powershell -NoProfile -ExecutionPolicy Bypass -File tools\send.ps1 -File cmds\NN_name.lua -Label "做了什麼"
powershell -NoProfile -ExecutionPolicy Bypass -File tools\send.ps1 -File q.lua -ReadOnly     # 查詢
powershell -NoProfile -ExecutionPolicy Bypass -File tools\analyze.ps1 renders\x.wav
```
程式碼一定要用檔案傳（PowerShell 會吃掉命令列參數裡的雙引號）。

## 規則
1. **先看狀態**：`bridge.ps1 status`。`blocked` = REAPER 開著對話框（看 `dialogs`），請使用者關掉，**不要 restart**。`stopped` → `bridge.ps1 start`。
2. **編輯前先 dump**，確認現況；使用者可能手動改過。不要覆蓋或刪除不是你建的軌道，除非使用者要求。
3. **指令留紀錄**：用 PowerShell 時，每個指令存成 `cmds/NN_簡短名稱.lua`（編號接續最大號），送出時給 `-Label`（就是 undo 名稱）。MCP 會自動存到 `cmds/mcp/`。查詢用 readonly。
4. **改完存檔**：`H.save()`。不要做會跳出對話框的事：關閉/結束 REAPER、對沒存過的專案存檔、開新專案。真的需要時先問使用者。
5. **聽不到聲音**：每次改音色/混音後 `H.render("<曲名>_vN")` → `analyze.ps1`，把重點寫進 `notes.md`，請使用者聽。
6. **多個 agent**：lock 只保證請求不會同時執行，不會幫你處理「兩個 agent 改同一軌」的衝突。開始前在回覆裡說明你要動哪些軌；動之前重新 dump。
7. **持續改進與測試**：修改 `bridge/`、`tools/`、`mcp/` 之後一定要跑
   `powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1`（約 1 分鐘，會在暫時的專案分頁跑，不會動到曲子）。
   新增 helper 時同時加測試（`tests/test_helpers.lua`）、更新 `bridge/API.md`、提升 `H.version`。測試失敗不可以略過或刪測試來讓它通過。
8. **回報問題**：遇到 bug、怪行為、繞過的方法，寫進 `ISSUES.md`（格式見該檔），並在回覆裡跟使用者說：發生什麼、原因、修了沒、還剩什麼風險。不要只說「完成了」。

## Git
- 預設分支 `main`。一個邏輯變更一個 commit；**commit 前跑測試**（只改曲子或文件時不用）。
- `renders/*.wav` 走 Git LFS（`.gitattributes`）。`Backups/`、`tests/tmp/`、`Media/` 不進版控。
- `.rpp` 設成不自動 merge：同一首曲子同時只能有一個人或一個 agent 改。曲子的變更要 commit 在 main 上（REAPER 開的就是 main checkout 裡的那份）。
- **worktree 的限制**：REAPER 載入的是 **main checkout** 的 `bridge/`（載入器寫死了路徑）。在 worktree 裡改 `bridge/` 不會影響正在跑的 bridge，在那裡跑 `tests\run-tests.ps1` 測到的也是 main 的版本（hot reload 測試還會失敗）。所以要改 bridge/helpers，請在 main checkout 改、測、commit；`tools/`、`mcp/`、`tests/`、文件可以在 worktree 改，但只有在 main 上合併後才算測過。
- 不要 commit 使用者沒同意的大型音檔或 Media。

## 已知的坑（細節見 ISSUES.md）
- FX 包絡線存的是 native 值：用 `H.automate_display`，不要用 normalized。
- 參數用 `H.set(track, fx, param, 顯示值或選項文字)`，並檢查回傳的顯示字串。
- 檔案已存在時 REAPER 會默默跳過 render：用 `H.render`（會先刪掉舊檔）。
- `-nonewinst` 偶爾會開出第二個 REAPER：只用 `tools\bridge.ps1` 啟動/重啟 bridge。
- Surge XT 參數名稱：`A Osc 1 Type`、`A Filter 1 Cutoff`、`A Amp EG Attack`…，用 `H.params(track, "Surge", "filter")` 找。
