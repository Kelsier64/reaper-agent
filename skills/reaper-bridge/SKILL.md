---
name: reaper-bridge
description: 透過 Lua bridge 操作使用者電腦上正在執行的 REAPER（DAW）：查狀態、讀取專案（軌道、MIDI、FX、automation、混音）、送 Lua（ReaScript + H helpers）來編曲或修改、存檔、render 成 WAV 並分析。只要使用者提到 REAPER、DAW、編曲、軌道、MIDI、音色、混音、render，或想讓你直接在 REAPER 裡做事，就用這個 skill，即使他沒有說「bridge」。Use whenever the user wants you to look at or change their open REAPER project.
---

# 操作 REAPER bridge

一個 Lua 腳本在 REAPER 裡持續執行（bridge），你用這個 skill 附的 CLI 把 Lua 送進去，拿回 JSON。
使用者會在中間手動調整，所以 REAPER 裡的現況永遠比你記得的可靠。
你聽不到聲音，所以每次動到聲音都要 render 再分析，最後請使用者聽。

下面的 `R` 是文件裡的簡寫，代表 `node "<skill>/scripts/reaper.mjs"`，`<skill>` 是這個 skill 的資料夾（載入 skill 時顯示的 Base directory）。
**執行時把它展開成完整的指令**，例如 `node "C:/Users/.../reaper-bridge/scripts/reaper.mjs" status`。
不要存成 shell 變數（`R=...; $R status`、`$s=...`）：Claude Code 之類的權限檢查看不到變數的內容，會直接擋掉這種指令。
一個指令只做一件事，不要用 `;` 串好幾個。相對路徑都以你目前的工作資料夾為準。

## 指令
| 指令 | 用途 |
|---|---|
| `R status` | bridge 狀態、開著的專案、REAPER 對話框、lock 持有者。**每次開始先跑。** |
| `R start [--project 檔案.rpp]` / `R restart` / `R stop` | 啟動 bridge（REAPER 沒開時會連 REAPER 一起開） |
| `R install` | 第一次使用：讓 REAPER 載入這個 skill 附的 bridge |
| `R dump [--notes] [--sends]` | 專案快照：tempo、拍號、軌道（音量、pan、FX、items）、regions、markers |
| `R exec 檔案.lua --label "做了什麼"` | 執行 Lua。一次請求 = 一個 undo 點 `Claude: <label>` |
| `R exec 檔案.lua --readonly` | 查詢，不建 undo 點 |
| `R exec - --label "..."` | 從 stdin 讀程式碼，自動存到 `cmds/cli/`（只適合很短的查詢，見「Shell 注意事項」） |
| `R render 名稱 [--start-bar N --end-bar N --tail 秒]` | master → `<REAPER 專案資料夾>/renders/名稱.wav`，會取代舊檔 |
| `R analyze 檔案.wav` | 峰值/RMS、頻段、頻譜峰、時間軸（怎麼讀：`reaper-sound-design` skill） |
| 任何指令加 `--out 檔案` | 完整輸出寫到檔案，只印摘要。大的 dump 用這個，再讀需要的部分 |

Exit code：0 成功、1 用法錯誤、2 bridge 沒在跑或被擋住、3 timeout、4 Lua 執行錯誤、5 lock 被佔用太久、6 install 被拒絕。

## 流程
1. **`R status`**，依 `bridge` 欄位處理：
   - `running` → 繼續。如果輸出有 `skill.warning`，代表 REAPER 跑的 helpers 版本跟這份文件不同，跟使用者說一聲並小心檢查結果。
   - `blocked` → REAPER 開著對話框（看 `dialogs`）。**請使用者關掉，不要 restart**：restart 會在對話框關掉後又多開一個 REAPER。
   - `stopped` → `R start`。`reaper-not-running` → `R start --project <使用者的 .rpp>`，或請使用者自己打開 REAPER。
   - `installed: false` → 第一次使用，見 `references/troubleshooting.md` 的「第一次設定」。
   - 其他狀況（sandbox 擋住、timeout、lock 很久）→ `references/troubleshooting.md`。
2. **`R dump`**（要看音符就 `R dump --notes --out <暫存檔>`）。使用者可能手動改過；
   不是你建的軌道不要覆蓋或刪除，除非使用者要求。
3. **在回覆裡先說明你要動哪些軌**。可能有其他 agent 也在操作同一個 REAPER：lock 只會讓請求排隊，不會避免兩邊改同一軌。
4. **寫 Lua 前讀 `references/api.md`**（H helpers 的完整說明），常用寫法見 `references/examples.md`。
5. 修改用的程式碼存成檔案：放在目前工作資料夾的 `cmds/NN_簡短名稱.lua`（`NN` 接續最大編號，沒有就建立 `cmds/`），
   讓使用者事後看得到你做過什麼。然後 `R exec cmds/NN_xxx.lua --label "做了什麼"`。
6. 檢查回應（見下方），最後 `H.save()`（可以寫在同一個指令的最後）。
7. 動到聲音就 render → analyze → 記錄 → 請使用者聽。細節在 `reaper-sound-design` skill。

## 寫 Lua 的重點
環境裡有 `reaper`（完整 ReaScript API，別名 `r`）、`H`（helpers）、`log(...)`。`return` 的值會轉成 JSON 回來
（MediaTrack 這類指標會變成字串，請回傳名稱或 index）。

- **bar** 從 1 開始，可以是小數；**MIDI item 內的音符位置**是從 item 開頭算的四分音符數（QN）。
- track = 名稱、1-based index 或 MediaTrack；fx = 0-based index 或名稱片段；param = index、名稱或片段。
- 參數用 `H.set(track, fx, param, 顯示值或選項文字)`，**並檢查回傳的顯示字串**：
  外掛的 normalized 值跟顯示值通常不是線性關係，不檢查就可能差很多。
- Automation 用 `H.automate_display`，不要用 normalized 值（理由同上）。

## 回應格式
```json
{"id":"…","ok":true,"result":…,"log":["…"],"bridge":"2.0.0","helpers":"2.0.0","helpers_error":null}
```
- `ok:false` → 看 `error`。錯誤發生前已做的修改還在同一個 undo 點裡：跟使用者說明，或自己送指令修正。
- `helpers_error` 有值 → helpers 檔案壞了，bridge 正在用上一版。告訴使用者。

## Shell 注意事項
- **Lua 一律先寫成檔案**（用你的寫檔工具，查詢用的可以放暫存資料夾），再 `R exec 檔案`。這是最可靠的方式：
  - PowerShell 會吃掉傳給外部程式的參數裡的雙引號，用管線送中文到 stdin 也可能變亂碼。
  - bash 的 heredoc 裡只要 Lua 同時有 `{` 和引號（幾乎每段都有），Claude Code 的權限檢查就會當成可疑的展開而擋掉。
- `R exec -`（stdin）只留給沒有大括號和引號的極短查詢，例如 `return H.project_file()`。
- `--label` 不要放雙引號。
- `render` 可能要好幾分鐘：shell 指令的 timeout 設 10 分鐘，或放到背景執行。

## 不能做的事
會跳出對話框的動作會讓 bridge 卡住，直到使用者手動關掉：關閉或結束 REAPER、關閉有未存變更的專案、
開新專案、對從沒存過的專案存檔（`H.save()` 會直接報錯，不會開 Save As）。真的需要時先問使用者。

## 遇到問題
bug、怪行為、你繞過的方法：如果目前資料夾有 `ISSUES.md` 就照它的格式記下來；否則在回覆裡說清楚
發生什麼、可能的原因、你怎麼處理、還剩什麼風險。不要只說「完成了」。
