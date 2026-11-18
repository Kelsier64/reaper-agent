---
name: reaper-bridge
description: 操作正在執行的 REAPER（DAW）：查 bridge 狀態、dump 專案、送 Lua（ReaScript + H helpers）修改軌道/MIDI/FX/automation、存檔、render。任何要讀取或修改目前 REAPER 專案的工作都先讀這個 skill。Use for any task that reads or edits the open REAPER project through tools/reaper.mjs.
---

# 操作 REAPER bridge

所有操作都透過 `node tools/reaper.mjs`（在專案根目錄執行）。它會呼叫 `tools/send.ps1`，
處理 lock、timeout、heartbeat。輸出是 bridge 回傳的 JSON。

## 指令
| 指令 | 用途 |
|---|---|
| `status` | bridge 狀態、開著的專案、REAPER 對話框、lock 持有者。**第一步一定先跑。** |
| `start [--project p.rpp]` / `restart` / `stop` | 啟動 bridge（必要時連 REAPER 一起開）。`restart` 只在改了 `bridge/bridge.lua` 時需要 |
| `dump [--notes] [--sends]` | 專案快照：tempo、拍號、軌道（音量、pan、FX、items）、regions、markers |
| `exec <file.lua> --label "..."` | 執行 Lua，一次請求 = 一個 undo 點 `Claude: <label>` |
| `exec <file.lua> --readonly` | 查詢，不建 undo 點 |
| `exec - --label "..."` | 從 stdin 讀程式碼（bash heredoc 用），自動存到 `cmds/cli/` |
| `render <name> [--start-bar N --end-bar N --tail S]` | master → `renders/<name>.wav`（會取代舊檔） |
| `analyze <file.wav>` | 峰值/RMS、頻段、頻譜峰、時間軸（見 `reaper-sound-design`） |
| 任何指令加 `--out <file>` | 完整輸出寫到檔案，只印 `{"ok","exit","out","bytes"}`。大的 dump 用這個，再讀需要的部分 |

Exit code：0 成功、1 用法錯誤、2 bridge 沒在跑或被擋住、3 timeout、4 Lua 執行錯誤、5 lock 被佔用太久。

## 標準流程
1. **`status`**，看 `bridge`：
   - `running` → 繼續。
   - `blocked` → REAPER 開著對話框（看 `dialogs`）。**請使用者關掉，不要 restart。**
   - `stopped` → `start`。`reaper-not-running` → `start --project <曲子>.rpp`。
   - `lock` 有值 → 另一個 agent 正在送請求，等一下就好（會自動排隊）。
2. **`dump`**（要看音符就 `dump --notes --out tests/tmp/dump.json`）。使用者可能手動改過；
   不是你建的軌道不要覆蓋或刪除，除非使用者要求。
3. 在回覆裡先說明你要動哪些軌（可能有其他 agent 同時在改）。
4. **讀 `bridge/API.md`**，寫成 `cmds/NN_簡短名稱.lua`（`NN` = `cmds/` 裡最大編號 + 1）。
5. `exec cmds/NN_xxx.lua --label "做了什麼"`，檢查回應（見下方）。
6. 結尾 `H.save()`（可以直接寫在同一個指令的最後）。
7. 動到聲音就做 render → analyze → 寫 `notes.md` → 請使用者聽（`reaper-sound-design`）。

## 寫 Lua
環境裡有 `reaper`（完整 ReaScript API，別名 `r`）、`H`（helpers）、`log(...)`/`print(...)`。
`return` 的值會轉成 JSON 回來（MediaTrack 之類的指標會變成字串，請回傳名稱或 index）。

重點慣例（完整版在 `bridge/API.md`）：
- **bar** 從 1 開始，可以是小數（`2.5` = 第 2 小節的一半）。
- **MIDI item 內的音符位置**是從 item 開頭算的四分音符數（QN）。3/8 拍一小節 = 1.5 QN。
- track = 軌道名稱、1-based index 或 MediaTrack；fx = 0-based index 或名稱片段；param = index、完整名稱或片段。
- 參數一律用 `H.set(track, fx, param, 顯示值或選項文字)`，**並檢查回傳的顯示字串**。

範例：
```lua
local tr = H.get_or_add_track("Bass", { vol_db = -6 })
H.fx(tr, "Surge XT")
local take = H.midi_item(tr, 2, 8, { name = "bass A" })
H.add_notes(take, { { "A1", 0, 1.5, 96 }, { "E2", 1.5, 1.5, 90 } })
H.save()
return H.items(tr)
```

## 回應格式
```json
{"id":"…","ok":true,"result":…,"log":["…"],"bridge":"2.0.0","helpers":"2.0.0","helpers_error":null}
```
- `ok:false` → 看 `error`。錯誤發生前已做的修改還在同一個 undo 點裡：跟使用者說明，或自己送指令修正。
- `helpers_error` 有值 → `bridge/helpers.lua` 壞了，bridge 正在用上一版（見 `reaper-bridge-dev`）。

## Shell 注意事項
- **PowerShell 會吃掉傳給外部程式的參數裡的雙引號**：Lua 一律寫成檔案再 `exec <file>`，`--label` 不要放雙引號。
  PowerShell 用管線送中文到 stdin 也可能變亂碼，所以在 PowerShell 裡不要用 `exec -`。
- bash 可以用 heredoc：
  ```bash
  node tools/reaper.mjs exec - --readonly <<'EOF'
  return H.fx_list("Melody")
  EOF
  ```
- `render` 可能要好幾分鐘（CLI 自己的上限是 600 s）。shell 指令的 timeout 要設夠長，或放到背景執行。
- bridge 會讀寫 `%APPDATA%\REAPER\Scripts\ClaudeBridge\`，這個位置在專案資料夾外面。
  如果你的 sandbox（例如 Codex 的 workspace-write）擋住了，請使用者核准，或改用允許寫入這個位置的模式。
  不要自己繞過 sandbox。

## 不能做的事
會跳出對話框的動作會讓 bridge 卡住，直到使用者手動關掉：
- 關閉或結束 REAPER、關閉有未存變更的專案、開新專案。
- 對從沒存過的專案存檔（`H.save()` 會直接報錯，不會開 Save As）。
- 部分 render 設定、外掛的錯誤視窗。

真的需要時先問使用者。

## 遇到問題
寫進 `ISSUES.md`（格式見該檔，新的放最上面），並在回覆裡說明：發生什麼、原因、修了沒、還剩什麼風險。
