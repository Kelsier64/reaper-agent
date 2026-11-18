---
name: reaper-bridge
description: 透過 Lua bridge 操作使用者電腦上正在執行的 REAPER（DAW）：查狀態、讀取專案（軌道、MIDI、FX、automation、混音）、送 Lua（ReaScript + H helpers）來編曲或修改、存檔、render 成 WAV、分析，並把結果交給使用者試聽（直接傳 WAV、試聽頁、在 REAPER 裡設好播放範圍）。只要使用者提到 REAPER、DAW、編曲、軌道、MIDI、音色、混音、render、遊戲音樂/音效，或想讓你直接在 REAPER 裡做事，就用這個 skill，即使他沒有說「bridge」。Use whenever the user wants you to look at, change, render or play back their REAPER project.
---

# 操作 REAPER bridge

一個 Lua 腳本在 REAPER 裡持續執行（bridge），你用這個 skill 附的 CLI 把 Lua 送進去，拿回 JSON。
使用者會在中間手動調整、也會切換專案分頁，所以 REAPER 裡的現況永遠比你記得的可靠。
你聽不到聲音：每次動到聲音都要 render、分析，然後**把結果用最省事的方式交給使用者聽**（見「交付試聽」）。

下面的 `R` 是文件裡的簡寫，代表 `node "<skill>/scripts/reaper.mjs"`，`<skill>` 是這個 skill 的資料夾（載入 skill 時顯示的 Base directory）。
**執行時把它展開成完整的指令**，例如 `node "C:/Users/.../reaper-bridge/scripts/reaper.mjs" status`。
不要存成 shell 變數（`R=...; $R status`、`$s=...`）：Claude Code 之類的權限檢查看不到變數的內容，會直接擋掉這種指令。
一個指令只做一件事，不要用 `;` 串好幾個。

## 指令
| 指令 | 用途 |
|---|---|
| `R status` | bridge 狀態、作用中的專案（`status.project`）、REAPER 對話框、lock。**每次開始先跑** |
| `R start [--project 檔案.rpp]` / `R restart` / `R stop` | 啟動 bridge（REAPER 沒開時會連 REAPER 一起開） |
| `R install` | 第一次使用：讓 REAPER 載入這個 skill 附的 bridge |
| `R dump [--notes] [--sends]` | 專案快照（欄位說明在 `references/api.md` 的 dump 一節） |
| `R exec 檔案.lua --project 曲名 --label "做了什麼"` | 執行 Lua。一次請求 = 一個 undo 點 `Claude: <label>` |
| `R exec 檔案.lua --readonly` | 查詢，不建 undo 點 |
| `... --arg 名稱=值`（可重複） | 傳參數給 Lua：程式裡用 `ARGS.名稱`（像數字的會變成數字）。同一支腳本換數值不用多寫一個檔 |
| `R render 名稱 [--start-bar N --end-bar N --tail 秒 --srate 48000 --mono]` | master → `<專案資料夾>/renders/名稱.wav`，取代舊檔，並更新同資料夾的試聽頁 |
| `R listen [--from N --to N --tracks "A,B" --play --no-loop]` | 在 REAPER 裡設好循環範圍、游標、畫面縮放、選取軌道，使用者按空白鍵就能聽 |
| `R page [--open]` | 產生/開啟試聽頁 `renders/listen.html`（每個 WAV 一個播放器，加上說明） |
| `R analyze 檔案.wav` | 峰值/RMS、頻段、頻譜峰、時間軸（怎麼讀：`reaper-sound-design` skill） |
| 任何指令加 `--out 檔案` | 完整輸出寫到檔案，只印摘要。大的 dump 用這個，再讀需要的部分 |

Exit code：0 成功、1 用法錯誤、2 bridge 沒在跑或被擋住、3 timeout、4 Lua 執行錯誤（包括 `--project` 不符）、5 lock 被佔用太久、6 install 被拒絕。

## 流程
1. **`R status`**，依 `bridge` 欄位處理：
   - `running` → 繼續。輸出有 `skill.warning` 代表 REAPER 跑的 helpers 版本跟這份文件不同，告訴使用者並小心檢查結果。
   - `blocked` → REAPER 開著對話框（看 `dialogs`）。**請使用者關掉，不要 restart**：restart 會在對話框關掉後又多開一個 REAPER。
   - `stopped` → `R start`。`reaper-not-running` → `R start --project <使用者的 .rpp>`，或請使用者自己打開 REAPER。
   - `installed: false` 或其他狀況 → `references/troubleshooting.md`。
2. **確認目標專案**：`status.project` 是不是你要改的那首？REAPER 可以開好幾個專案分頁，所有指令都作用在**目前選取的分頁**。
   之後**每個修改指令都加 `--project <曲名>`**：使用者中途切分頁時，指令會報錯而不是改到別首。要做新曲子 → 見「開一首新曲子」。
3. **`R dump --project <曲名>`**。使用者可能手動改過；不是你建的軌道不要覆蓋或刪除，除非使用者要求。
4. **在回覆裡先說明你要動哪些軌**。可能有其他 agent 也在操作同一個 REAPER：lock 只會讓請求排隊，不會避免兩邊改同一軌。
5. **寫 Lua 前讀 `references/api.md`**，常用寫法見 `references/examples.md`。
6. 修改用的程式碼存成檔案：放在**曲子專案資料夾**的 `cmds/NN_簡短名稱.lua`（`status.project` 所在的資料夾；`NN` 接續最大編號），
   讓使用者事後看得到你做過什麼。然後 `R exec <那個檔案> --project <曲名> --label "做了什麼"`。
7. 檢查回應（見下方），最後 `H.save()`（寫在同一個指令的最後）。
8. 動到聲音 → render → analyze → **交付試聽**。

## 開一首新曲子
agent 不能自己開新專案或另存新檔：這兩個動作都會跳出對話框卡住 bridge。
1. 跟使用者確認曲子要放哪裡、叫什麼，例如 `<遊戲>/audio/music/<曲名>/<曲名>.rpp`。可以先幫他建好資料夾。
2. 請使用者在 REAPER 選 **File > New project tab**，再用 **File > Save project as…** 存到那個路徑。
   提醒他：原本開著的其他曲子分頁可以留著，你會用 `--project` 確認只改新的這首。
3. `R status`，確認 `status.project` 是新檔。接著 `H.set_tempo(bpm, 拍號)`、建軌，照一般流程進行。

## 交付試聽
使用者要的是「打開就能聽」，不是一串路徑。每次 render 之後：
1. 在 WAV 旁邊寫一個同名的 `.txt`（例如 `renders/曲名_v3.txt`），兩三行就好：這版改了什麼、請注意聽哪裡（用 `m:ss`）。
   試聽頁會把它顯示在播放器下方。
2. `R render` 已經自動更新試聽頁。這個 session 第一次交付時加跑 `R page --open` 打開它；之後只要請使用者重新整理。
3. 如果你有把檔案直接傳給使用者的工具（例如 Claude 桌面版的 `SendUserFile`），**直接把 WAV 傳過去**，
   多個候選放在同一次傳送，附一行說明。沒有這種工具時，給 WAV 的完整路徑連結。
4. 跑 `R listen --project <曲名> --from <小節> --to <小節> --tracks "<你改的軌>"`，
   讓使用者想在 REAPER 裡聽（或 solo 某軌）時，按空白鍵就從重點段落開始循環。除非使用者要求，不要加 `--play`：突然出聲很嚇人。
5. 回覆用這個格式（表格 + 一個具體問題）：

   | 版本 | 檔案 | 改了什麼 | 注意聽 |
   |---|---|---|---|
   | v3 | [曲名_v3.wav](完整路徑) | 主旋律換成窄脈波 | 0:05 第一句的音色、0:20 進入 B 段 |

   接著問一個好回答的問題，例如「A 和 B 哪個比較像你要的？」「0:20 的喇叭感是太重還是剛好？」，
   並附上試聽頁連結；REAPER 裡已經設好從第幾小節循環也要說。

## 寫 Lua 的重點
環境裡有 `reaper`（完整 ReaScript API，別名 `r`）、`H`（helpers）、`log(...)`，加 `--arg` 時還有 `ARGS`。
`return` 的值會轉成 JSON 回來（MediaTrack 這類指標會變成字串，請回傳名稱或 index）。

- **bar** 從 1 開始，可以是小數；**MIDI item 內的音符位置**是從 item 開頭算的四分音符數（QN）。
- track = 名稱、1-based index 或 MediaTrack；fx = 0-based index 或名稱片段；param = index、名稱或片段（`H.params` 的篩選可用 `^` 比對開頭）。
- 參數用 `H.set(track, fx, param, 顯示值或選項文字)`，**並檢查回傳的顯示字串**：
  外掛的 normalized 值跟顯示值通常不是線性關係，不檢查就可能差很多。
- Automation 用 `H.automate_display`，並比對回傳每一點的 `want`（你要的）和 `display`（實際的顯示值）。

## 回應格式
```json
{"id":"…","ok":true,"result":…,"log":["…"],"bridge":"2.0.0","helpers":"3.0.0","helpers_error":null}
```
- `ok:false` → 看 `error`。錯誤發生前已做的修改還在同一個 undo 點裡：跟使用者說明，或自己送指令修正。
  `require_project: active project is X` → 使用者切了分頁，請他切回來，**不要自己切**。
- `helpers_error` 有值 → helpers 檔案壞了，bridge 正在用上一版。告訴使用者。

## Shell 注意事項
- **Lua 一律先寫成檔案**（用你的寫檔工具），再 `R exec 檔案`。這是最可靠的方式：
  - PowerShell 會吃掉傳給外部程式的參數裡的雙引號，用管線送中文到 stdin 也可能變亂碼。
  - bash 的 heredoc 裡只要 Lua 同時有 `{` 和引號（幾乎每段都有），Claude Code 的權限檢查就會當成可疑的展開而擋掉。
- `R exec -`（stdin）只留給沒有大括號和引號的極短查詢，例如 `return H.project_file()`；它會存到專案資料夾的 `cmds/cli/`。
- `--label` 不要放雙引號。`render` 可能要好幾分鐘：shell 指令的 timeout 設 10 分鐘，或放到背景執行。

## 不能做的事
會跳出對話框的動作會讓 bridge 卡住，直到使用者手動關掉：關閉或結束 REAPER、關閉有未存變更的專案、
開新專案、對從沒存過的專案存檔（`H.save()` 會直接報錯，不會開 Save As）。也不要自己切換專案分頁。真的需要時先問使用者。

## 遇到問題
bug、怪行為、你繞過的方法：如果目前資料夾有 `ISSUES.md` 就照它的格式記下來；否則在回覆裡說清楚
發生什麼、可能的原因、你怎麼處理、還剩什麼風險。不要只說「完成了」。
