-- Taiwan garbage-truck tone: square-wave melody chip -> overdriven horn loudspeaker -> street echo
local report = {}
local function P(tr, fx, name, v) report[#report + 1] = name .. " = " .. H.set(tr, fx, name, v) end

local function chip_patch(tr)
  local fx = H.fx(tr, "Surge XT")
  P(tr, fx, "A Osc 1 Shape", 100)          -- classic osc -> square
  P(tr, fx, "A Osc 1 Width 1", 50)
  P(tr, fx, "A Osc 2 Mute", "Off")         -- turn on osc 2
  P(tr, fx, "A Osc 2 Shape", 100)
  P(tr, fx, "A Osc 2 Octave", 1)           -- one octave up, quieter: shrill organ-ish chip tone
  P(tr, fx, "A Osc 2 Volume", -11)
  P(tr, fx, "A Osc Drift", 4)              -- cheap chip clock wobble
  P(tr, fx, "A Amp EG Attack", 2)
  P(tr, fx, "A Amp EG Decay", 500)
  P(tr, fx, "A Amp EG Sustain", 55)
  P(tr, fx, "A Amp EG Release", 90)
  P(tr, fx, "A Volume", -4)
  return fx
end

-- bus
local spk = H.get_or_add_track("Loudspeaker", { color = "#EB5757" })
while reaper.TrackFX_GetCount(spk) > 0 do reaper.TrackFX_Delete(spk, 0) end

local sat = H.fx(spk, "JS: Saturation", { new = true })
P(spk, sat, "Amount (%)", 60)

local eq = H.fx(spk, "ReaEQ", { new = true })
P(spk, eq, "Freq-High Pass 5", 480)        -- horn: no bass
P(spk, eq, "Freq-Low Shelf", 250)
P(spk, eq, "Gain-Low Shelf", -8)
P(spk, eq, "Freq-Band 2", 900)
P(spk, eq, "Gain-Band 2", 2)
P(spk, eq, "Freq-Band 3", 1700)            -- horn honk
P(spk, eq, "Gain-Band 3", 7)
P(spk, eq, "BW-Band 3", 1.2)
P(spk, eq, "Freq-High Shelf 4", 4200)      -- no air
P(spk, eq, "Gain-High Shelf 4", -22)

local dly = H.fx(spk, "ReaDelay", { new = true })
P(spk, dly, "Wet", -11)
P(spk, dly, "1: Length (musical)", 0)
P(spk, dly, "1: Length (time)", 130)       -- slap off buildings
P(spk, dly, "1: Feedback", -14)
P(spk, dly, "1: Lowpass", 3000)
P(spk, dly, "1: Hipass", 500)

local verb = H.fx(spk, "ReaVerbate", { new = true })
P(spk, verb, "Wet", -16)
P(spk, verb, "Room size", 65)
P(spk, verb, "Dampening", 70)
P(spk, verb, "Hipass", 400)
P(spk, verb, "Lowpass", 5000)

local lim = H.fx(spk, "JS: Master Limiter", { new = true })
P(spk, lim, "Threshold (dB)", -6)

-- instruments -> bus (mono-ish, centered)
for _, name in ipairs({ "Melody", "Accomp" }) do
  local tr = H.track(name)
  chip_patch(tr)
  reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", 0)
  if reaper.GetTrackNumSends(tr, 0) == 0 then H.send(tr, spk, 0) end
  H.mix(tr, { pan = 0 })
end
H.mix("Accomp", { vol_db = -5 })
reaper.Main_SaveProject(0, false)
return { report = report, dump = H.dump() }
