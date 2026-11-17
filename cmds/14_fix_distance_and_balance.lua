-- fix truck movement automation (use display values) + rebalance wet buses
local dist = H.track("Distance")
-- bar, direct level dB, pan, air-loss shelf dB
local path = {
  { 1, -22, -60, -14 }, { 10, -11, -35, -7 }, { 16, -4, -15, -2 }, { 18, 0, 0, 0 },
  { 23, 0, 10, 0 }, { 26, -6, 35, -4 }, { 31, -16, 60, -10 }, { 34, -30, 75, -16 },
}
local function col(i) local t = {} for k, p in ipairs(path) do t[k] = { p[1], p[i], 2 } end return t end
local res = {}
res.vol = H.automate_display(dist, "Volume/Pan", "Volume (dB)", col(2))
res.pan = H.automate_display(dist, "Volume/Pan", "Pan", col(3))
res.shelf = H.automate_display(dist, "ReaEQ", "Gain-High Shelf 4", col(4))

-- wet buses: lower, so the direct horn dominates when the truck is close
local spk = H.track("Loudspeaker")
for i = 0, reaper.GetTrackNumSends(spk, 0) - 1 do
  local _, dn = reaper.GetTrackName(reaper.GetTrackSendInfo_Value(spk, 0, i, "P_DESTTRACK"))
  if dn == "Street Echo" then reaper.SetTrackSendInfo_Value(spk, 0, i, "D_VOL", H.db2vol(-15)) end
  if dn == "Street Reverb" then reaper.SetTrackSendInfo_Value(spk, 0, i, "D_VOL", H.db2vol(-12)) end
end
-- balance the two reflections (left one was louder)
local echo = H.track("Street Echo")
res.e1 = H.set(echo, 0, "Wet", -3)
res.e2 = H.set(echo, 1, "Wet", 0)
reaper.Main_SaveProject(0, false)
return res
