# 外掛參數筆記

參數名稱會隨外掛版本變動，以 `H.params(track, fx, "關鍵字")` 查到的為準。

## Surge XT（免費合成器）
- 參數以場景開頭：`A Osc 1 Type`、`A Osc 1 Shape`、`A Osc 2 Mute`、`A Filter 1 Type`、`A Filter 1 Cutoff`、
  `A Amp EG Attack` / `Decay` / `Sustain` / `Release`。B 場景就是 `B …`。
- 超過 1 秒的時間會顯示成 `"1.50 s"`；`H.set` 一律用 ms 比對，傳 `1500`。
- **已知問題**：`A Amp EG Attack` 設不到很小的值（傳 2 ms 會變成 `0.0 ms`），attack 實際接近 0，可能有一點 click。
  需要很短但不是 0 的 attack 時，跟使用者說明這個限制。
- Mute 之類的開關是選項：`H.set(tr, "Surge", "A Osc 2 Mute", "On")`。
- 常見音色起點：
  - 方波晶片音：Osc 1 Classic、Shape 100%（方波）、width 50%；Amp EG A 0 / D 500 ms / S 55% / R 90 ms。
  - 柔和 pad：saw + unison 3 voices、LP 24 dB 約 900 Hz、A 900 ms / R 2.5 s。
  - 鐘聲：sine + FM（Osc 2 高八度再 +7 半音）、D 700 ms、S 0。
  - 環境底噪：noise（color 往負）、LP 24 dB 約 400 Hz、一個長音、音量很低。

## ReaEQ
- 參數名稱會跟著頻段類型變：一般頻段是 `Freq-Band 2`（Hz）、`Gain-Band 2`（dB）、`BW-Band 2`；
  shelf 頻段是 `Freq-Low Shelf`、`Gain-High Shelf 4` 這種。預設的 ReaEQ 第 1 段是 low shelf、最後一段是 high shelf。
  先用 `H.params(track, "ReaEQ", "Freq")` 看實際名稱。
- 最小增益顯示 `-inf`，用 `-200` 設。

## ReaDelay / ReaVerbate
- 做空間感時放在獨立的效果軌，100% wet，用 send 控制量（`H.ensure_send(src, fx_track, -12)`）。
- 左右不同的延遲時間（例如 170 ms / 290 ms）可以做出寬度，但結果會不對稱：用 analyze 的 `L-R` 檢查。

## JS 效果（REAPER 內建）
- `JS: Volume/Pan Adjustment`：拿來做軌道音量/pan automation。
- `JS: Saturation`、`JS: Master Limiter`：失真/喇叭感、最後一級限制。
- JS slider 的 normalized 跟顯示值不是線性：automation 一律用 `H.automate_display`。

## 安裝新外掛之後
REAPER 要重新掃描才看得到：請使用者重開 REAPER 或在 Preferences > Plug-ins 按 Re-scan。沒有不跳對話框的 API。
