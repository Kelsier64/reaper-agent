---
name: reaper-bridge-dev
description: 修改 reaper-agent 本身的工具：bridge/bridge.lua、bridge/helpers.lua（H helpers）、tools/reaper.mjs 等 CLI、tests/、以及 .agents/skills 裡的 skills。Use when adding or fixing a helper, changing the bridge protocol or CLI, editing tests, or editing these skills.
---

# 修改 bridge、CLI、測試、skills

## 在哪裡改
- REAPER 載入的是 **main checkout** 的 `bridge/`（載入器寫死了路徑，見 `tools/install.ps1`）。
  - 在 worktree 裡改 `bridge/` 不會影響正在跑的 bridge，在那裡跑測試測到的也是 main 的版本。
  - 所以 **bridge/helpers 一律在 main checkout 改、測、commit**。
  - `tools/`、`tests/`、skills、文件可以在 worktree 改，但只有在 main 上合併並跑過測試才算測過。
- `bridge/helpers.lua`：存檔即生效（熱重載）。寫壞時 bridge 繼續用上一版，回應裡的 `helpers_error` 會寫原因。
- `bridge/bridge.lua`：改完要 `node tools/reaper.mjs restart`。只用這個（或 `tools/bridge.ps1`）重啟，
  自己用 `-nonewinst` 送腳本可能會開出第二個 REAPER。

## 新增或修改 helper
1. 改 `bridge/helpers.lua`。
2. 在 `tests/test_helpers.lua` 加測試（它在暫時的專案分頁跑，不會動到曲子）。
3. 更新 `bridge/API.md`。
4. 提升 `H.version`（`bridge/helpers.lua` 開頭）。
5. 如果影響到 agent 的操作方式，一起更新相關的 skill。

## 修改 CLI（`tools/reaper.mjs`）
- 它只是包裝 `tools/send.ps1` / `bridge.ps1` / `analyze.ps1`。lock、timeout、heartbeat 的邏輯留在 PowerShell 裡，不要複製一份。
- 測試在 `tests/test_cli.mjs`（用子程序呼叫 CLI，跟 agent 的用法一樣）。

## 修改 skills
- 原始檔在 `.agents/skills/<name>/SKILL.md`（Codex 讀這裡）。
- 改完跑 `node tools/sync-skills.mjs`，把內容複製到 `.claude/skills/`（Claude Code 讀這裡）。
- `.claude/skills/` 不要直接改，測試（`skills` 套件）會檢查兩邊是否一致、frontmatter 是否正確。

## 測試
```
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 -Only cli,skills
```
- 套件：`analyze`、`protocol`、`helpers`、`cli`、`skills`。結果在 `tests/last-run.log`。
- 除了 `analyze` 和 `skills`，都需要 bridge 在跑。
- 改了 `bridge/`、`tools/`、`tests/`、skills 之後一定要跑。**測試失敗不可以略過或刪測試來讓它通過。**

## 回報與 commit
- bug、怪行為、繞過的方法寫進 `ISSUES.md`：`### [OPEN|FIXED|WORKAROUND|WONTFIX] 標題`，加日期、現象、原因、處理方式；
  修好時改狀態並註明是哪個測試在防止它再發生。
- 一個邏輯變更一個 commit，commit 前跑測試。
- 在 PowerShell 裡 commit 訊息先寫成 UTF-8 檔案，再 `git commit -F <檔案>`。
