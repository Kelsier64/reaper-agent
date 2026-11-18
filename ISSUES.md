# 問題紀錄

格式：`### [狀態] 標題` 加上日期、現象、原因、處理方式。狀態：`OPEN` / `FIXED` / `WORKAROUND` / `WONTFIX`。
新的寫在最上面。修好時把狀態改掉，並註明是哪個測試在防止它再發生。

---

### [FIXED] apocalypseRV 實戰回報的 skill 問題（10 項）
- 2026-11-18。另一個 session 用已安裝的 skills 做了 Slender Speaker 的曲子，流程沒有失敗，但回報了這些問題，全部在 helpers 3.0.0 / CLI 1.2.0 處理：
  1. 多個專案分頁沒有防呆，使用者切分頁時指令會改到別首 → `H.require_project`、CLI `--project`。測試：`helpers: require_project guards the active tab`、`cli: --project mismatch`。
  2. `H.automate_display` 回傳 native 值，ReaEQ/Surge 無法對照 → 回傳 `{bar, want, display, native}`。測試：`automate_display reports display values for non-dB native units (ReaEQ)`。
  3. `cmds/`、stdin 紀錄跑到 agent 的工作資料夾（那次剛好是這個 repo）→ 預設放在 REAPER 專案資料夾。
  4. 沒有「開新曲子」流程 → reaper-bridge skill 新增一節。
  5. Lua 腳本不能帶參數 → `--arg k=v`（`ARGS`）。測試：`cli: --arg strings and numbers`。
  6. render 只能 44.1 kHz 立體聲 → `--srate`、`--mono`。測試：`render srate/channels: 48 kHz mono`。
  7–8. 候選沒對齊響度、遠近效果的 send 位置 → 寫進 reaper-sound-design。
  9. dump 欄位沒文件、沒有 master → API.md 加 dump 欄位，dump 加 `master`。
  10. `H.params` 只能子字串、analyze 對單聲道印 -150 dB → `^` 開頭比對、analyze 標 `mono`。
- 同時新增試聽交付：`listen`（REAPER 裡設好循環範圍）、試聽頁 `renders/listen.html`、WAV 旁的 `.txt` 說明、有傳檔工具時直接傳 WAV。
  用 `claude -p` 在暫時的 TrialSong 分頁實測過整個流程，沒有被權限檢查擋住。

### [FIXED] `H.render` 會蓋掉專案自己的 render 設定，並讓專案變成未存檔
- 2026-11-18。還原 Distance 並存檔後做了一次檢查 render，專案又變成 `[modified]`，之後的存檔把 render 目標寫成
  `tests\tmp\restore_check.wav`。使用者自己在 REAPER 裡設定的 render 路徑、檔名、範圍也會被蓋掉。
- 原因：`H.render` 直接改寫 `RENDER_FILE`/`RENDER_PATTERN`/範圍/格式，render 完沒有改回去。
- 修正（helpers 2.1.0）：render 前記住這些設定、結束後（包括出錯時）改回去；render 前是乾淨的專案會再存一次以保持乾淨，
  原本就有未存變更的不會替使用者存。回傳多了 `saved_project`。曲子的 render 設定用 `cmds/18_restore_render_settings.lua` 改回 v2 的值。
  測試：`helpers: render restores the project's render settings and dirty state`。

### [WORKAROUND] Claude Code 的權限檢查擋掉 skill 示範的指令寫法
- 2026-11-18。用 `claude -p` 在 repo 外測試已安裝的 skills：兩個 skill 都正確觸發，但各被擋了一次。
  - `R=".../reaper.mjs"; $R status`（PowerShell 也一樣：`$s=...`）→ "A variable in this command can't be checked before it runs"。
  - bash heredoc 送 Lua（`exec - <<'EOF'`，內容有 `{` 和引號）→ "Contains brace with quote character (expansion obfuscation)"。
- 原因：skill 用 `R` 當簡寫，agent 照字面設成 shell 變數；heredoc 是 skill 推薦的寫法之一。兩次 agent 都自己改用完整路徑和寫檔，成功完成。
- 處理：skills 改成明確要求展開完整路徑、不要用變數、Lua 先寫檔再 `exec`；stdin 只留給極短查詢。CLAUDE.md 同步更新。
  重跑三個測試（列軌道、分析 WAV、查 Surge 參數）都沒有再被擋。目前沒有自動測試，只能用 `claude -p` 手動重跑。

### [OPEN] Surge XT 的 Amp EG Attack 設不到很小的值（2 ms 會變成 0.0 ms）
- 2026-11-18。`H.set(track, "Surge", "A Amp EG Attack", 2)` 回傳 `0.0 ms`。
- 推測：Surge 在接近 0 的區間顯示值會四捨五入，binary search 落在顯示 "0.0" 的區域。還沒確認實際的 attack 是多少。
- 影響：晶片音色的 attack 實際接近 0（聽起來可能有點 click）。
- 待做：掃描 normalized 0–0.1 的顯示值找出對應關係，必要時讓 `set_param_display` 改用最接近的顯示值。

### [OPEN] v2 結尾殘響偏左約 1.5 dB
- 2026-11-18。`analyze` 時間軸 36 s 處 L-R +1.6 dB，車子這時應該在右邊。
- 原因：Street Echo/Reverb 不跟著車子的 pan 移動，左右兩道反射也不對稱。
- 待做：讓 Street Echo 的平衡跟著 Distance 的 pan automation 走，或降低左邊反射。等使用者聽過再決定。

### [FIXED] analyze.ps1 的 peak/RMS 是單聲道混音的值
- 2026-11-18。左右不平衡時 peak 會少報（測試：左 -6 dB 的正弦波報成 -8.5 dB）。v1/v2 報告中的 peak 都受影響。
- 修正：peak 取各聲道真實樣本峰值、RMS 取各聲道平均。頻譜仍然用單聲道混音。測試：`analyze: peak = -6.0 dBFS`。
- v2 修正後：peak -0.1 dBFS、RMS -16.9 dBFS（舊報告寫的是 -17.6）。

### [FIXED] `-nonewinst` 送腳本時意外開出第二個 REAPER
- 2026-11-18。restart 時，主程式正在停止腳本、來不及回應，啟動器就自己變成了新的 REAPER（空專案 + 兩個 "REAPER" 對話框），bridge 啟動失敗。
- 修正：`bridge.ps1` 會檢查啟動器有沒有在 6 秒內結束；沒有的話只關掉剛剛那個程序，等 2 秒後重試，最多 3 次。stop 和 start 之間也多等 2 秒。`status` 會列出 `extra_instances`。

### [FIXED] FX 包絡線用 normalized 值換算錯誤（v2 第一次 render 車子沒有靠近）
- 2026-11-18。JS Volume 的 0 dB 被寫成 -24 dB；ReaEQ 增益也錯。
- 原因：FX 包絡線存的是 native 值，而 JS slider / ReaEQ 的 normalized 跟 native 不是線性關係。
- 修正：`H.automate_display`（用顯示值 → 讀 native 值 → 寫入 → 回讀驗證）。`H.automate` 標為 deprecated。測試：`helpers: automate_display writes native values`。

### [FIXED] 檔案已存在時 REAPER 會默默跳過 render
- 2026-11-18。回傳成功，但檔案還是舊的，害分析結果跟上一版一模一樣。
- 修正：`H.render` 會先刪掉舊檔，並回傳 `replaced`。測試：`helpers: render writes and replaces a file`。

### [FIXED] 參數顯示值解析：`-inf`、開關選項、"s"/"ms" 單位
- 2026-11-18。EQ 增益最小值顯示 `-inf` 無法解析；`A Osc 2 Mute` 是 Off/On；Surge 超過 1 秒會顯示 "1.50 s"，被讀成 1.5 ms（Decay 被設成 32 s）。
- 修正：`H.parse_display`、`H.set_param_choice`、`H.set`。測試：`parse_display units`、`FX params`、`Surge XT seconds display`。

### [WORKAROUND] PowerShell 會吃掉命令列參數裡的雙引號
- 2026-11-18。`send.ps1 -Code "return H.chord(\"Fm7\")"` 送到 REAPER 時字串已經沒有引號了。
- 處理：程式碼一律存成檔案再用 `-File` 傳；`-Code` 參數已經拿掉。CLI（`tools/reaper.mjs`）也是讀檔或 stdin，不經過命令列參數。

### [WORKAROUND] 會跳出對話框的動作會卡住 bridge
- 2026-11-18。用 action 40004 結束 REAPER 時跳出 "REAPER Query"（是否儲存），必須由使用者手動點。
- 處理：`H.save()` 在沒存過的專案上會直接報錯，不會開 Save As；`bridge.ps1 status` 會列出對話框標題；CLAUDE.md 規定不要做這類動作。

### [WORKAROUND] REAPER 裝新外掛後要重開才會掃到
- 2026-11-18。Surge XT 裝完，`TrackFX_AddByName` 找不到。
- 處理：存檔後重開 REAPER（或請使用者在 Preferences > Plug-ins 按 Re-scan）。目前沒有不經對話框的 rescan API。
