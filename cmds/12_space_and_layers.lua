-- v2: depth + atmosphere
--   Loudspeaker (horn) -> Distance (direct, automated far->near->far, L->R)
--                      -> Street Echo (building reflections L/R)
--                      -> Street Reverb (big wet space)
--   new layers: Bell (chip 2nd voice, A'/A''), Dusk Pad (non-diegetic, from A'), City Ambience (noise bed)
local report = {}
local function P(tr, fx, name, v) report[#report + 1] = name .. " = " .. H.set(tr, fx, name, v) end
local function pidx(tr, fx, name)
  for _, p in ipairs(H.params(tr, fx, name)) do if p.name == name then return p.i end end
  error("param " .. name)
end
local function norm(tr, fx, name, disp) -- normalized value for a display value
  H.set(tr, fx, name, disp)
  return reaper.TrackFX_GetParamNormalized(tr, fx, pidx(tr, fx, name))
end
local function ensure_send(src, dst, db)
  src, dst = H.track(src), H.track(dst)
  for i = 0, reaper.GetTrackNumSends(src, 0) - 1 do
    if reaper.GetTrackSendInfo_Value(src, 0, i, "P_DESTTRACK") == dst then
      reaper.SetTrackSendInfo_Value(src, 0, i, "D_VOL", H.db2vol(db)); return
    end
  end
  H.send(src, dst, db)
end
local function clear_fx(tr) while reaper.TrackFX_GetCount(tr) > 0 do reaper.TrackFX_Delete(tr, 0) end end

---------------------------------------------------------------- buses
local spk = H.track("Loudspeaker")
-- keep only the horn part (saturation, EQ, limiter); space moves to its own buses
for i = reaper.TrackFX_GetCount(spk) - 1, 0, -1 do
  local _, n = reaper.TrackFX_GetFXName(spk, i, "")
  if n:find("ReaDelay") or n:find("ReaVerbate") then reaper.TrackFX_Delete(spk, i) end
end
reaper.SetMediaTrackInfo_Value(spk, "B_MAINSEND", 0)

local dist = H.get_or_add_track("Distance", { color = "#BB6BD9" })
local echo = H.get_or_add_track("Street Echo", { color = "#2D9CDB" })
local verb = H.get_or_add_track("Street Reverb", { color = "#2F80ED" })
for _, t in ipairs({ dist, echo, verb }) do clear_fx(t) end
ensure_send(spk, dist, 0)
ensure_send(spk, echo, -8)
ensure_send(spk, verb, -5)

-- Distance: air loss + level + position
local deq = H.fx(dist, "ReaEQ", { new = true })
P(dist, deq, "Freq-High Shelf 4", 2500)
P(dist, deq, "BW-High Shelf 4", 1.0)
local dvp = H.fx(dist, "JS: Volume/Pan Adjustment (Cockos)", { new = true })

-- Street Echo: two reflections, left near wall then right far wall
local e1 = H.fx(echo, "ReaDelay", { new = true })
P(echo, e1, "Wet", 0); P(echo, e1, "Dry", -200)
P(echo, e1, "1: Length (musical)", 0); P(echo, e1, "1: Length (time)", 170)
P(echo, e1, "1: Feedback", -12); P(echo, e1, "1: Lowpass", 2500); P(echo, e1, "1: Hipass", 600)
P(echo, e1, "1: Pan", -0.6)
local e2 = H.fx(echo, "ReaDelay", { new = true })
P(echo, e2, "Wet", -3); P(echo, e2, "Dry", 0)
P(echo, e2, "1: Length (musical)", 0); P(echo, e2, "1: Length (time)", 290)
P(echo, e2, "1: Feedback", -16); P(echo, e2, "1: Lowpass", 2200); P(echo, e2, "1: Hipass", 700)
P(echo, e2, "1: Pan", 0.7)

-- Street Reverb: big, dark-ish, wide
local rv = H.fx(verb, "ReaVerbate", { new = true })
P(verb, rv, "Wet", 0); P(verb, rv, "Dry", -200)
P(verb, rv, "Room size", 92); P(verb, rv, "Dampening", 55)
P(verb, rv, "Delay", 25); P(verb, rv, "Hipass", 300); P(verb, rv, "Lowpass", 6500)

---------------------------------------------------------------- layers
-- Bell: chip 2nd voice, melody +12 in A' and A''
local bell = H.get_or_add_track("Bell", { color = "#F2994A", index = 3 })
clear_fx(bell)
local bfx = H.fx(bell, "Surge XT")
P(bell, bfx, "A Osc 1 Type", "Sine")
P(bell, bfx, "A Osc 2 Type", "Sine")
P(bell, bfx, "A Osc 2 Mute", "Off")
P(bell, bfx, "A Osc 2 Volume", -200)      -- osc 2 only as FM modulator
P(bell, bfx, "A Osc 2 Octave", 1)
P(bell, bfx, "A Osc 2 Pitch", 7)          -- ratio ~3: glockenspiel-ish
P(bell, bfx, "A FM Routing", "2 > 1")
P(bell, bfx, "A FM Depth", -12)
P(bell, bfx, "A Amp EG Attack", 0)
P(bell, bfx, "A Amp EG Decay", 700)
P(bell, bfx, "A Amp EG Sustain", 0)
P(bell, bfx, "A Amp EG Release", 500)
P(bell, bfx, "A Volume", -6)
reaper.SetMediaTrackInfo_Value(bell, "B_MAINSEND", 0)
ensure_send(bell, spk, 0)
H.mix(bell, { vol_db = -7 })
H.delete_items(bell)
local mel = H.get_notes(H.take("Melody", 1))
local bnotes = {}
for _, n in ipairs(mel) do
  local bar = math.floor(n.s / 1.5 + 1e-6) + 1
  if (bar >= 10 and bar <= 17) or (bar >= 24 and bar <= 31) then
    bnotes[#bnotes + 1] = { n.p + 12, n.s, n.l, 72 }
  end
end
H.add_notes(H.midi_item(bell, 1, 32, { name = "bell (melody +12)" }), bnotes)

-- Dusk Pad: warm detuned saw pad, outside the horn
local pad = H.get_or_add_track("Dusk Pad", { color = "#9B51E0" })
clear_fx(pad)
local pfx = H.fx(pad, "Surge XT")
P(pad, pfx, "A Osc 1 Shape", 0)            -- saw
P(pad, pfx, "A Osc 1 Unison Voices", "3 voices")
P(pad, pfx, "A Osc 1 Unison Detune", 14)
P(pad, pfx, "A Filter 1 Type", "LP 24 dB")
P(pad, pfx, "A Filter 1 Cutoff", 900)
P(pad, pfx, "A Filter 1 Resonance", 12)
P(pad, pfx, "A Amp EG Attack", 900)
P(pad, pfx, "A Amp EG Decay", 1500)
P(pad, pfx, "A Amp EG Sustain", 80)
P(pad, pfx, "A Amp EG Release", 2500)
P(pad, pfx, "A Volume", -6)
H.mix(pad, { vol_db = -17 })
ensure_send(pad, verb, -4)
H.delete_items(pad)
local A_H = { "E5", "Am", "E", "Am", "E5", "Am", "E" }
local harm = { false }
local function add(l) for _, c in ipairs(l) do harm[#harm + 1] = c end end
add(A_H); add({ "Am" }); add(A_H); add({ "Am" })
add({ "C", "G", "Am", "E", "E5", "E5" })
add(A_H); add({ "Am" })
local vel = function(bar) if bar < 18 then return 55 elseif bar < 24 then return 78 else return 64 end end
local pnotes = {}
for bar = 10, #harm do
  local len = (bar == #harm) and 4.5 or 1.5
  for _, p in ipairs(H.chord(harm[bar], 3)) do
    pnotes[#pnotes + 1] = { p, (bar - 1) * 1.5, len, vel(bar) }
  end
end
H.add_notes(H.midi_item(pad, 1, 34, { name = "dusk pad" }), pnotes)

-- City Ambience: dark noise bed, whole song
local amb = H.get_or_add_track("City Ambience", { color = "#4F4F4F" })
clear_fx(amb)
local afx = H.fx(amb, "Surge XT")
P(amb, afx, "A Osc 1 Mute", "On")
P(amb, afx, "A Noise Mute", "Off")
P(amb, afx, "A Noise Color", -60)
P(amb, afx, "A Filter 1 Type", "LP 24 dB")
P(amb, afx, "A Filter 1 Cutoff", 380)
P(amb, afx, "A Amp EG Attack", 3000)
P(amb, afx, "A Amp EG Sustain", 100)
P(amb, afx, "A Amp EG Release", 4000)
H.mix(amb, { vol_db = -24 })
ensure_send(amb, verb, -10)
H.delete_items(amb)
H.add_notes(H.midi_item(amb, 1, 34, { name = "city hum" }), { { "C3", 0, 49.5, 100 } })

---------------------------------------------------------------- truck movement
-- bar, direct level dB, pan, air-loss shelf dB
local path = {
  { 1, -22, -60, -14 }, { 10, -11, -35, -7 }, { 16, -4, -15, -2 }, { 18, 0, 0, 0 },
  { 23, 0, 10, 0 }, { 26, -6, 35, -4 }, { 31, -16, 60, -10 }, { 34, -30, 75, -16 },
}
local vpts, ppts, spts = {}, {}, {}
for _, p in ipairs(path) do
  vpts[#vpts + 1] = { p[1], norm(dist, dvp, "Volume (dB)", p[2]), 2 }
  ppts[#ppts + 1] = { p[1], norm(dist, dvp, "Pan", p[3]), 2 }
  spts[#spts + 1] = { p[1], norm(dist, deq, "Gain-High Shelf 4", p[4]), 2 }
end
H.automate(dist, dvp, "Volume (dB)", vpts, { clear = true })
H.automate(dist, dvp, "Pan", ppts, { clear = true })
H.automate(dist, deq, "Gain-High Shelf 4", spts, { clear = true })
report[#report + 1] = "pan@1 display = " .. H.set(dist, dvp, "Pan", -60)

-- master safety limiter
local master = reaper.GetMasterTrack(0)
local ml = H.fx(master, "JS: Master Limiter")
P(master, ml, "Threshold (dB)", -2)

reaper.Main_SaveProject(0, false)
return { report = report, dump = H.dump() }
