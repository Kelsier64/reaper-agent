---
name: reaper-sound-design
description: 在 REAPER 裡設計音色、調合成器與效果器參數（Surge XT、ReaEQ、ReaDelay、ReaVerbate、JS 效果）、做 automation、調音量與 pan、做遊戲音樂與音效，並用 render + analyze 客觀檢查、再交給使用者試聽比較（你聽不到聲音）。使用者說「音色」「聲音太悶/太亮」「加點空間感」「混音」「左右不平衡」「這版聽起來怎樣」「做幾個版本給我挑」或要你調任何效果參數時都用這個 skill。需要搭配 reaper-bridge skill。Use when changing synth patches, effects, levels, panning, automation, making game audio, or evaluating and comparing renders.
---

# 音色設計與混音

這個 skill 搭配 `reaper-bridge` 使用：CLI 在它的資料夾裡，也就是這個 skill 旁邊的 `../reaper-bridge/`。
下面的 `R` 是文件裡的簡寫，代表 `node "<skill>/../reaper-bridge/scripts/reaper.mjs"`。
執行時展開成完整路徑，不要存成 shell 變數（權限檢查會擋掉含變數的指令）；Lua 先寫成檔案再 `R exec 檔案`。
先照 `reaper-bridge` 的流程做（status → 確認專案 → dump → 說明要動哪些軌），這裡只講音色、檢查和試聽。

## 開始前先問清楚
做錯方向最浪費時間（例如把「怪物頭上喇叭放的歌」做成了背景配樂），所以先確認：
- **聲音從哪裡來**：遊戲世界裡的聲源（收音機、喇叭、角色身上；要乾聲、單聲道，讓遊戲做 3D 定位和距離）
  還是背景配樂（BGM；可以有殘響、立體聲寬度）？
- **參考**：有沒有具體想像的聲音（「像台灣垃圾車」）？越像越好，還是只要那個感覺？
- **交付規格**：長度、要不要無縫循環、取樣率和聲道（遊戲常用 48 kHz、單聲道：`R render 名稱 --srate 48000 --mono`）。
- **哪些不用做**：例如其他音效由遊戲引擎處理，就不要自己加進音樂裡。

## 找參數、設參數
外掛參數動輒幾百個，名稱也各家不同，所以先查再設：
```lua
return H.params("Lead", "Surge", "^A Filter")   -- "^" 比對開頭；不加就是子字串
```
- **`H.set(track, fx, param, value)`**：數字 = **顯示值**（`800` Hz、`-6` dB、`1500` ms；`-200` 可以設到 `-inf`），
  字串 = **選項文字**（`"LP 24 dB"`、`"On"`；清單用 `H.param_choices` 查）。
- **一定要看回傳的顯示字串**。normalized 值跟顯示值多半不是線性關係，H.set 用搜尋找最接近的值，
  有些範圍（例如非常小的時間）根本設不到，只有回傳值會告訴你實際結果。
- 時間一律用 ms 傳（1.5 秒傳 `1500`），即使外掛顯示成 `"1.50 s"`。
- 外掛名稱用 `H.installed_fx("關鍵字")` 查。各外掛的參數名稱和已知問題：`references/plugins.md`。

## Automation
- 用 **`H.automate_display(track, fx, param, { {bar, 顯示值, shape?}, ... })`**。
  回傳每一點的 `{bar, want, display, native}`：**比對 `want` 和 `display`**。`native` 是 envelope 存的內部值，
  每個外掛單位不同（JS 是 dB，ReaEQ 增益是線性倍數），不要拿它跟你要的數字比。
- 軌道本身的音量/pan 沒有包裝函式：加 `JS: Volume/Pan Adjustment` 再 automate 它的參數。
- shape：0 linear、1 square、2 slow start/end、3 fast start、4 fast end、5 bezier。

## 每次改完：render → analyze → 記錄 → 交付試聽
1. 版本名稱用 `<曲名>_vN`，N 接續 `renders/` 裡最大的版本；同一版的候選加 `_A`、`_B`。
   遊戲用的檔案直接用遊戲要的規格 render（`--srate 48000 --mono`）。
2. `R render <名稱> --project <曲名>`（只看一段：`--start-bar 10 --end-bar 18`）。
3. `R analyze <回傳的 path>`。怎麼讀：`references/analyze-output.md`。
4. **給候選比較之前先對齊響度**：各候選的 RMS 差到 1 dB 以內（調 master 或該軌音量後重新 render）。
   人耳會覺得比較大聲的比較好，不對齊的話使用者選的其實是音量。對齊後在說明裡寫「已對齊到約 -18 dBFS RMS」。
5. 記錄在曲子專案資料夾的 `notes.md`（沒有就建立）：改了什麼（訊號流程、參數）、分析數字、還有疑慮的地方。
6. **交付試聽**：照 `reaper-bridge` 的「交付試聽」做——寫 `.txt` 說明、直接傳 WAV（有工具時）、試聽頁、
   `R listen` 設好 REAPER 的循環範圍、表格加一個具體的問題。把使用者的回饋也寫進 `notes.md`。

分析只能證明「數字照預期變了」，不能證明「好聽」。不要只憑分析就說改好了。

## 判斷方向的經驗法則
- 「太悶」→ 看 2–8 kHz 的頻段能量；「太刺」→ 看 2–5 kHz 和頻譜峰；「太薄」→ 看 150–500 Hz。
- 「沒有空間感」→ 看 `side/mid`（接近 0 dB 才寬）；加 delay/reverb 用 send 到效果軌，比直接掛在音源上好調。
- 「遠近」→ 音量 + 高頻衰減（high shelf 往下）+ 濕訊號比例一起動，只動音量聽起來只是變小聲。
  **送到殘響/回音的 send 要接在距離 automation 之後**（從距離軌送出，或 post-fader），
  否則乾聲變遠了、殘響還是一樣大，遠處聽起來跟近處一樣大聲。用 analyze 的時間軸確認遠處的 RMS 真的有下降。
- pan automation 只會移動乾訊號；殘響和回音的平衡要另外處理，否則結尾容易偏一邊。
- 遊戲世界裡的聲源要乾聲：空間感、距離、方向交給遊戲引擎，音樂裡加了殘響反而會「不在那個位置」。
