# 疑難排解

## 第一次設定
需要：Windows、REAPER、Node.js 18 以上、Windows PowerShell 5.1（Windows 內建）。

1. `R install`：在 `%APPDATA%\REAPER\Scripts\ClaudeBridge\ClaudeBridge.lua` 寫一個載入器，指向這個 skill 的 `bridge/` 資料夾。
   - 回傳 exit 6 / `"REAPER already uses another bridge"`：REAPER 已經在用別的 bridge（例如開發版的 repo）。
     **不要加 `--force`**，直接用現有的 bridge 就好（協定相同）；`R status` 的 `skill.warning` 會告訴你版本是否一致。
     只有使用者明確要求切換時才用 `R install --force`。
2. `R start`（REAPER 沒開會先打開它）。
3. `R status` 應該顯示 `"bridge":"running"`。

## status 的欄位
| 欄位 | 意思 |
|---|---|
| `bridge` | `running` / `stopped`（REAPER 開著，bridge 沒跑）/ `blocked`（有 heartbeat 但超過 10 秒沒更新）/ `reaper-not-running` |
| `dialogs` | REAPER 目前顯示的對話框標題。`blocked` 時通常就是這些擋住了 |
| `status.project` | 目前開著的 .rpp。`renders/` 會建在它旁邊 |
| `status.root` | REAPER 實際載入的 bridge 資料夾 |
| `status.helpers` | REAPER 實際跑的 helpers 版本 |
| `lock` | 正在送請求的程序：`PID|時間|label`。其他 agent 在用時會出現，請求會自動排隊 |
| `extra_instances` | 多開的 REAPER（不該出現）。請使用者關掉多的那個 |
| `skill` | 只有從安裝的 skill 執行才會有：這份文件對應的版本，以及版本不一致時的 `warning` |

## 常見狀況
- **`require_project: active project is X, expected Y`**：使用者在 REAPER 切到了別的專案分頁（或你給錯名稱）。
  請使用者切回 Y 那個分頁再繼續；不要自己切分頁，也不要拿掉 `--project` 硬做。- **`blocked`**：請使用者關掉 `dialogs` 裡列的視窗。不要 restart，也不要 stop：對話框關掉之後 REAPER 會處理排隊的動作，可能多開一個 REAPER。
- **exit 3 timeout**：請求太久（render）或中途跳出對話框。先 `R status` 看看。render 本身最多給 600 秒。
- **exit 5 lock busy**：另一個請求佔用超過 300 秒。`R status` 看 `lock` 是誰；持有的程序已經不在時，下一個請求會自動接手。
- **`helpers_error`**：bridge 載入 helpers 失敗，正在用上一版。這是 bridge 本身的問題，告訴使用者。
- **sandbox 擋住寫入**：bridge 透過 `%APPDATA%\REAPER\Scripts\ClaudeBridge\` 的檔案溝通，這個位置在工作資料夾外面。
  Codex 的 workspace-write 之類的 sandbox 可能會擋。請使用者核准或改用允許的模式，**不要自己想辦法繞過 sandbox**。
- **找不到剛裝的外掛**：REAPER 要重新掃描外掛（重開 REAPER，或在 Preferences > Plug-ins 按 Re-scan）。請使用者處理。
- **render 回傳成功但檔案沒變**：REAPER 遇到同名檔案會默默跳過；`R render` 會先刪掉舊檔，用它就不會遇到。
- **多開了一個 REAPER**：只用 `R start` / `R restart` 啟動 bridge，不要自己用 `reaper.exe -nonewinst` 送腳本。
