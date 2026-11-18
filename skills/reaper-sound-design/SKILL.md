---
name: reaper-sound-design
description: 在 REAPER 裡設計音色、調合成器與效果器參數（Surge XT、ReaEQ、ReaDelay、ReaVerbate、JS 效果）、做 automation、調音量與 pan，並用 render + analyze 客觀檢查結果（你聽不到聲音）。使用者說「音色」「聲音太悶/太亮」「加點空間感」「混音」「左右不平衡」「這版聽起來怎樣」或要你調任何效果參數時都用這個 skill。需要搭配 reaper-bridge skill。Use when changing synth patches, effects, levels, panning, automation, or evaluating a render.
---

# 音色設計與混音

這個 skill 搭配 `reaper-bridge` 使用：CLI 在它的資料夾裡，也就是這個 skill 旁邊的 `../reaper-bridge/`。
下面的 `R` 是文件裡的簡寫，代表 `node "<skill>/../reaper-bridge/scripts/reaper.mjs"`。
執行時展開成完整路徑，不要存成 shell 變數（權限檢查會擋掉含變數的指令）；Lua 先寫成檔案再 `R exec 檔案`。
先照 `reaper-bridge` 的流程做（status → dump → 說明要動哪些軌），這裡只講音色和檢查。

## 找參數、設參數
外掛參數動輒幾百個，名稱也各家不同，所以先查再設：
```lua
return H.params("Lead", "Surge", "filter")   -- { {i, name, v(normalized), fmt(顯示值)}, ... }
```
- **`H.set(track, fx, param, value)`**：數字 = **顯示值**（`800` Hz、`-6` dB、`1500` ms；`-200` 可以設到 `-inf`），
  字串 = **選項文字**（`"LP 24 dB"`、`"On"`；清單用 `H.param_choices` 查）。
- **一定要看回傳的顯示字串**。normalized 值跟顯示值多半不是線性關係，H.set 用搜尋找最接近的值，
  有些範圍（例如非常小的時間）根本設不到，只有回傳值會告訴你實際結果。
- 時間一律用 ms 傳（1.5 秒傳 `1500`），即使外掛顯示成 `"1.50 s"`。
- 外掛名稱用 `H.installed_fx("關鍵字")` 查。各外掛的參數名稱和已知問題：`references/plugins.md`。

## Automation
- 用 **`H.automate_display(track, fx, param, { {bar, 顯示值, shape?}, ... })`**，並檢查回傳的評估值。
  FX envelope 存的是外掛的 native 值，自己算 normalized 很容易錯（曾經把 0 dB 寫成 -24 dB）。
- 軌道本身的音量/pan 沒有包裝函式：加 `JS: Volume/Pan Adjustment` 再 automate 它的參數。
- shape：0 linear、1 square、2 slow start/end、3 fast start、4 fast end、5 bezier。

## 每次改完：render → analyze → 記錄 → 請使用者聽
1. 版本名稱用 `<專案名>_vN`，N 接續 REAPER 專案資料夾 `renders/` 裡最大的版本。
2. `R render <專案名>_vN`（只看一段：`--start-bar 10 --end-bar 18`）。回傳的 `path` 就是 WAV 的位置。
3. `R analyze <path>`。怎麼讀：`references/analyze-output.md`。
4. 記錄在 REAPER 專案資料夾的 `notes.md`（`status.project` 旁邊；沒有就建立）：
   改了什麼（訊號流程、參數）、分析數字、還有疑慮的地方。下一個接手的人（或 agent）靠它知道前因後果。
5. 請使用者聽：告訴他你預期會聽到什麼、想要哪一段的回饋。把回饋也寫進 `notes.md`。

分析只能證明「數字照預期變了」，不能證明「好聽」。不要只憑分析就說改好了。

## 判斷方向的經驗法則
- 「太悶」→ 看 2–8 kHz 的頻段能量；「太刺」→ 看 2–5 kHz 和頻譜峰；「太薄」→ 看 150–500 Hz。
- 「沒有空間感」→ 看 `side/mid`（接近 0 dB 才寬）；加 delay/reverb 用 send 到效果軌，比直接掛在音源上好調。
- 「遠近」→ 音量 + 高頻衰減（high shelf 往下）+ 濕訊號比例一起動，只動音量聽起來只是變小聲。
- pan automation 只會移動乾訊號；殘響和回音的平衡要另外處理，否則結尾容易偏一邊。
