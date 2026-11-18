# 常用寫法

完整 API 在 `api.md`。這裡是組合起來的例子，由上到下可以在同一個專案裡依序執行
（開發版的測試就是這樣跑的；假設專案裡已經有一軌 `Melody`，上面掛了 Surge XT 和一段 MIDI）。

## 查詢（--readonly）
```lua
-- 某一軌的 FX 和 items
return { fx = H.fx_list("Melody"), items = H.items("Melody") }
```
```lua
-- 某個 item 的音符（QN 從 item 開頭算）
return H.get_notes(H.take("Melody", 1))
```
```lua
-- 找參數（外掛參數很多，一定要加 filter）
return H.params("Melody", "Surge", "Filter 1 Cutoff")
```

## 新增一軌和一段 MIDI
```lua
local tr = H.get_or_add_track("Bass", { vol_db = -6, color = "#3366cc" })
H.fx(tr, "Surge XT")                         -- 已經有就不會重複加
local take = H.midi_item(tr, 2, 8, { name = "bass A" })   -- 第 2 小節開始，8 小節長
H.add_notes(take, {
  { "A1", 0,   1.5, 96 },                    -- {音高, 開始 QN, 長度 QN, 力度}
  { "E2", 1.5, 1.5, 90 },
})
H.save()
return H.items(tr)
```

## 和弦
```lua
local tr = H.get_or_add_track("Pad", { vol_db = -10 })
local take = H.midi_item(tr, 10, 4)
local notes = {}
for i, name in ipairs({ "Am", "F", "C", "G" }) do
  for _, p in ipairs(H.chord(name, 3)) do
    notes[#notes + 1] = { p = p, s = (i - 1) * 1.5, l = 1.5, v = 70 }   -- 每個和弦 1.5 QN（3/8 拍剛好一小節）
  end
end
H.add_notes(take, notes)
H.save()
return #H.get_notes(take)
```

## 設參數並確認
```lua
H.fx("Pad", "ReaEQ")
local got = {
  eq_freq = H.set("Pad", "ReaEQ", "Freq-Band 2", 900),              -- 顯示值（Hz）
  eq_gain = H.set("Pad", "ReaEQ", "Gain-Band 2", -6),               -- 顯示值（dB）
  attack  = H.set("Bass", "Surge", "A Amp EG Attack", 300),         -- 顯示值（ms）
  mute    = H.set("Bass", "Surge", "A Osc 2 Mute", "On"),           -- 選項文字
}
H.save()
return got   -- 回傳的是實際顯示字串，檢查是不是你要的
```

## 音量 automation（由遠而近再離開）
```lua
local tr = H.get_or_add_track("Distance")
H.fx(tr, "JS: Volume/Pan Adjustment")
local check = H.automate_display(tr, "Volume/Pan", "Volume", {
  { 1, -22 }, { 10, -11 }, { 18, 0 }, { 31, -16 },
})
H.save()
return check   -- 實際評估出來的值
```

## 送到 bus
```lua
local bus = H.get_or_add_track("Bus")
for _, name in ipairs({ "Bass", "Pad" }) do
  H.ensure_send(name, bus, 0)          -- 已經有就只更新音量
  H.mix(name, { master_send = false })
end
H.save()
return H.sends("Bass")
```
