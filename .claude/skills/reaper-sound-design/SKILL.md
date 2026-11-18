---
name: reaper-sound-design
description: 在 REAPER 裡設計音色、調 FX/合成器參數（Surge XT、ReaEQ、ReaDelay、ReaVerbate、JS 效果）、做 automation、調音量與 pan，並用 render + analyze 客觀檢查結果（agent 聽不到聲音）。Use when changing synth patches, effects, levels, panning, automation, or evaluating a mix.
---

# 音色設計與混音

先照 `reaper-bridge` 的流程（status → dump → 說明要動哪些軌）。這個 skill 只講音色和檢查。

## 找參數、設參數
```lua
-- 找參數名稱（Surge XT 有幾百個參數，一定要加 filter）
return H.params("Melody", "Surge", "filter")   -- { {i, name, v, fmt}, ... }
```
- **`H.set(track, fx, param, value)`**：
  - 數字 = **顯示值**：`800`（Hz）、`-6`（dB）、`1500`（ms）。`-200` 可以設到 `-inf`。
  - 字串 = **選項文字**：`"LP 24 dB"`、`"On"`。選項清單用 `H.param_choices(track, fx, param)` 查。
  - **一定要檢查回傳的顯示字串**，確認真的設到你要的值。
- 時間單位：Surge 超過 1 秒會顯示 `"1.50 s"`，`H.set` 一律用 ms 比對，所以 1.5 秒請傳 `1500`。
- 顯示值搜尋假設顯示值隨 normalized 單調變化。不是單調的參數用 `H.set_param`（0..1）並自己回讀確認。
- Surge XT 參數名稱的樣子：`A Osc 1 Type`、`A Filter 1 Cutoff`、`A Amp EG Attack`、`A Osc 2 Mute`。
- 外掛名稱用 `H.installed_fx("關鍵字")` 查。剛裝的外掛要重開 REAPER 才掃得到（請使用者處理）。

## Automation
- **用 `H.automate_display(track, fx, param, points, {clear, shape})`**，points 是 `{ {bar, 顯示值, shape?}, ... }`。
  它會回傳實際評估出來的值，**檢查它**。不要用已棄用的 `H.automate`（normalized 值對非線性參數是錯的）。
- 軌道本身的音量/pan envelope 沒有包裝函式：在軌道上加 `JS: Volume/Pan Adjustment (Cockos)`，再 automate 它的參數。
- Shapes：0 linear、1 square、2 slow start/end、3 fast start、4 fast end、5 bezier。

## Render → analyze → 記錄
每次改完音色或混音都要做：
1. 版本名稱用 `<曲名>_vN`，N 接續 `renders/` 裡最大的版本。
2. `node tools/reaper.mjs render <曲名>_vN`（只聽一段：`--start-bar 10 --end-bar 18`）。
3. `node tools/reaper.mjs analyze renders/<曲名>_vN.wav`。
4. 把改了什麼、分析重點、還有疑慮的地方寫進 `notes.md`（照現有的段落格式加一節）。
5. 請使用者聽，說明你預期他會聽到什麼、想聽哪個段落的回饋。

### 怎麼讀 analyze 的輸出
- `peak`：各聲道真實樣本峰值。接近 0 dBFS 表示有 limiter 在頂或可能削波。
- `rms` / `crest`：整體響度與動態（crest = peak − RMS；很小代表被壓得很扁）。
- `band energy`：各頻段相對最大頻段的 dB。用來確認 EQ、濾波器有沒有照預期作用。
- `strongest peaks`：最強的頻譜峰，可以對照音高或共振。
- `timeline`（每 3 秒）：
  - `rms dBFS`：音量變化，看漸強漸弱、段落對比。
  - `L-R dB`：左右平衡，正值 = 偏左。拿來檢查 pan automation 有沒有照預期移動。
  - `side/mid dB`：立體聲寬度。越接近 0 越寬，很負 = 接近單聲道。

分析只能證明「數字對不對」，不能證明「好不好聽」：一定要請使用者聽，並把他的回饋寫進 `notes.md`。

## 已知的坑（細節見 `ISSUES.md`）
- Surge XT 的 `A Amp EG Attack` 設不到很小的值（2 ms 會變成 `0.0 ms`）。
- 殘響、回音不會跟著主訊號的 pan automation 移動，結尾容易左右不平衡。
- 檔案已存在時 REAPER 會默默跳過 render：用 CLI 的 `render`（`H.render` 會先刪掉舊檔）。
