-- helpers.lua - the H table available to every bridge request.
-- Hot-reloaded by bridge.lua when this file changes. Must `return H`.
-- Bump H.version when you change behavior, add a test in tests/test_helpers.lua,
-- and document it in bridge/API.md.
local ctx = ... or {}
local encode = ctx.encode or function(v) return tostring(v) end

local H = {}
H.version = "2.0.0"

local function round(x, d) local m = 10 ^ (d or 4); return math.floor(x * m + 0.5) / m end
H.round = round
H.encode = encode
function H.db2vol(db) return 10 ^ (db / 20) end
function H.vol2db(v) if v <= 1e-8 then return -150 end return 20 * math.log(v, 10) end

---------------------------------------------------------------- time
-- Bars are 1-based and may be fractional (2.5 = halfway through bar 2).
-- Positions inside MIDI items are quarter notes (QN) from the item start.
function H.bar_qn(bar)
  local whole = math.floor(bar)
  local _, qs, qe = reaper.TimeMap_GetMeasureInfo(0, whole - 1)
  return qs + (bar - whole) * (qe - qs)
end
function H.bar_time(bar) return reaper.TimeMap2_QNToTime(0, H.bar_qn(bar)) end
function H.time_bar(t)
  local beat, measures, cml = reaper.TimeMap2_timeToBeats(0, t)
  return round(measures + 1 + beat / cml, 4)
end
function H.set_tempo(bpm, num, den)
  if reaper.CountTempoTimeSigMarkers(0) > 0 then
    local _, tpos, _, _, obpm, onum, oden, lin = reaper.GetTempoTimeSigMarker(0, 0)
    reaper.SetTempoTimeSigMarker(0, 0, tpos, -1, -1, bpm or obpm, num or onum, den or oden, lin)
  elseif num then
    reaper.SetTempoTimeSigMarker(0, -1, 0, -1, -1, bpm or reaper.Master_GetTempo(), num, den or 4, false)
  else
    reaper.SetCurrentBPM(0, bpm, true)
  end
  reaper.UpdateTimeline()
end

---------------------------------------------------------------- notes / chords
local NOTE = { C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 }
function H.n(x) -- "C4" -> 60, "F#2" -> 42, "Eb4" -> 63; numbers pass through
  if type(x) == "number" then return x end
  local l, acc, oct = tostring(x):match("^([A-Ga-g])([#b]*)(-?%d+)$")
  if not l then error("bad note name: " .. tostring(x), 2) end
  local v = NOTE[l:upper()] + (tonumber(oct) + 1) * 12
  for c in acc:gmatch(".") do v = v + (c == "#" and 1 or -1) end
  return v
end
local QUAL = {
  [""] = {0,4,7}, maj = {0,4,7}, m = {0,3,7}, min = {0,3,7}, ["5"] = {0,7},
  ["7"] = {0,4,7,10}, maj7 = {0,4,7,11}, m7 = {0,3,7,10}, mmaj7 = {0,3,7,11},
  dim = {0,3,6}, dim7 = {0,3,6,9}, m7b5 = {0,3,6,10}, aug = {0,4,8},
  sus2 = {0,2,7}, sus4 = {0,5,7}, ["7sus4"] = {0,5,7,10},
  add9 = {0,4,7,14}, madd9 = {0,3,7,14}, ["6"] = {0,4,7,9}, m6 = {0,3,7,9},
  ["9"] = {0,4,7,10,14}, maj9 = {0,4,7,11,14}, m9 = {0,3,7,10,14},
  ["11"] = {0,4,7,10,14,17}, m11 = {0,3,7,10,14,17}, ["13"] = {0,4,7,10,14,21},
}
H.CHORD_QUALITIES = QUAL
function H.chord(sym, octave) -- "Fm7", 3 -> {53,56,60,63}
  local root, acc, q = tostring(sym):match("^([A-G])([#b]?)(.*)$")
  if not root or not QUAL[q] then error("unknown chord: " .. tostring(sym), 2) end
  local base = H.n(root .. acc .. tostring(octave or 3))
  local out = {}
  for i, iv in ipairs(QUAL[q]) do out[i] = base + iv end
  return out
end

---------------------------------------------------------------- tracks
-- ref = exact name, 1-based index, or MediaTrack
function H.track(ref)
  if type(ref) == "userdata" then return ref end
  if type(ref) == "number" then return reaper.GetTrack(0, ref - 1) end
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    if name == ref then return tr end
  end
end
local function need_track(ref)
  local tr = H.track(ref)
  if not tr then error("track not found: " .. tostring(ref), 3) end
  return tr
end
H.need_track = need_track
local function native_color(c)
  local r, g, b
  if type(c) == "string" then
    local hex = c:gsub("#", "")
    r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
  else r, g, b = c[1], c[2], c[3] end
  return reaper.ColorToNative(r, g, b) | 0x1000000
end
function H.color(track, c) reaper.SetMediaTrackInfo_Value(need_track(track), "I_CUSTOMCOLOR", native_color(c)) end
function H.mix(track, o)
  local tr = need_track(track)
  if o.vol_db then reaper.SetMediaTrackInfo_Value(tr, "D_VOL", H.db2vol(o.vol_db)) end
  if o.pan then reaper.SetMediaTrackInfo_Value(tr, "D_PAN", o.pan) end
  if o.mute ~= nil then reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", o.mute and 1 or 0) end
  if o.solo ~= nil then reaper.SetMediaTrackInfo_Value(tr, "I_SOLO", o.solo and 1 or 0) end
  if o.master_send ~= nil then reaper.SetMediaTrackInfo_Value(tr, "B_MAINSEND", o.master_send and 1 or 0) end
  if o.color then H.color(tr, o.color) end
  if o.name then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", o.name, true) end
  return tr
end
function H.add_track(name, o)
  o = o or {}
  local idx = o.index and (o.index - 1) or reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name or "", true)
  H.mix(tr, o)
  return tr
end
function H.get_or_add_track(name, o) return H.track(name) or H.add_track(name, o) end
function H.delete_track(track) reaper.DeleteTrack(need_track(track)) end
function H.send(src, dst, vol_db)
  local s, d = need_track(src), need_track(dst)
  local idx = reaper.CreateTrackSend(s, d)
  if vol_db then reaper.SetTrackSendInfo_Value(s, 0, idx, "D_VOL", H.db2vol(vol_db)) end
  return idx
end
-- create the send if missing, otherwise just set its level (idempotent)
function H.ensure_send(src, dst, vol_db)
  local s, d = need_track(src), need_track(dst)
  for i = 0, reaper.GetTrackNumSends(s, 0) - 1 do
    if reaper.GetTrackSendInfo_Value(s, 0, i, "P_DESTTRACK") == d then
      if vol_db then reaper.SetTrackSendInfo_Value(s, 0, i, "D_VOL", H.db2vol(vol_db)) end
      return i
    end
  end
  return H.send(s, d, vol_db)
end
function H.sends(track)
  local tr = need_track(track)
  local out = {}
  for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local _, dn = reaper.GetTrackName(reaper.GetTrackSendInfo_Value(tr, 0, i, "P_DESTTRACK"))
    out[#out + 1] = { dest = dn, vol_db = round(H.vol2db(reaper.GetTrackSendInfo_Value(tr, 0, i, "D_VOL")), 2) }
  end
  return out
end

---------------------------------------------------------------- items / MIDI
function H.items(track)
  local tr = need_track(track)
  local out = {}
  for i = 0, reaper.CountTrackMediaItems(tr) - 1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
    local take = reaper.GetActiveTake(it)
    local name = ""
    if take then name = select(2, reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) end
    out[#out + 1] = { index = i + 1, item = it, take = take, name = name,
      start_bar = H.time_bar(pos), end_bar = H.time_bar(pos + len),
      midi = take ~= nil and reaper.TakeIsMIDI(take) }
  end
  return out
end
function H.take(track, index) local it = H.items(track)[index or 1]; return it and it.take end
function H.midi_item(track, start_bar, bars, o)
  local tr = need_track(track)
  local item = reaper.CreateNewMIDIItemInProj(tr, H.bar_qn(start_bar), H.bar_qn(start_bar + bars), true)
  local take = reaper.GetActiveTake(item)
  if o and o.name then reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", o.name, true) end
  return take, item
end
local function item_qn(take)
  local item = reaper.GetMediaItemTake_Item(take)
  return reaper.TimeMap2_timeToQN(0, reaper.GetMediaItemInfo_Value(item, "D_POSITION"))
end
-- notes: {pitch, start_qn, len_qn, vel, chan} or {p=,s=,l=,v=,ch=,mute=}; pitch number or "Eb4"
function H.add_notes(take, notes, o)
  o = o or {}
  local q0 = item_qn(take)
  for _, nt in ipairs(notes) do
    local p = H.n(nt.p or nt[1])
    local s = nt.s or nt[2] or 0
    local l = nt.l or nt[3] or 1
    local v = nt.v or nt[4] or o.vel or 100
    local ch = nt.ch or nt[5] or o.ch or 0
    local sp = reaper.MIDI_GetPPQPosFromProjQN(take, q0 + s)
    local ep = reaper.MIDI_GetPPQPosFromProjQN(take, q0 + s + l)
    v = math.max(1, math.min(127, math.floor(v + 0.5)))
    reaper.MIDI_InsertNote(take, false, nt.mute or false, sp, ep, ch, p, v, true)
  end
  reaper.MIDI_Sort(take)
  return #notes
end
function H.get_notes(take)
  local q0 = item_qn(take)
  local _, cnt = reaper.MIDI_CountEvts(take)
  local out = {}
  for i = 0, cnt - 1 do
    local _, _, mute, sp, ep, ch, p, v = reaper.MIDI_GetNote(take, i)
    local sq = reaper.MIDI_GetProjQNFromPPQPos(take, sp) - q0
    local eq = reaper.MIDI_GetProjQNFromPPQPos(take, ep) - q0
    out[#out + 1] = { p = p, s = round(sq, 4), l = round(eq - sq, 4), v = v, ch = ch, mute = mute or nil }
  end
  return out
end
function H.clear_notes(take)
  local _, cnt = reaper.MIDI_CountEvts(take)
  for i = cnt - 1, 0, -1 do reaper.MIDI_DeleteNote(take, i) end
end
-- delete items whose start is in [from_bar, to_bar); no bounds = all items
function H.delete_items(track, from_bar, to_bar)
  local tr = need_track(track)
  local n = 0
  for i = reaper.CountTrackMediaItems(tr) - 1, 0, -1 do
    local it = reaper.GetTrackMediaItem(tr, i)
    local b = H.time_bar(reaper.GetMediaItemInfo_Value(it, "D_POSITION"))
    if (not from_bar or b >= from_bar - 1e-6) and (not to_bar or b < to_bar - 1e-6) then
      reaper.DeleteTrackMediaItem(tr, it); n = n + 1
    end
  end
  return n
end

---------------------------------------------------------------- FX / params
-- fx = 0-based index or name substring; param = 0-based index, exact name, or substring
local function fx_name(tr, i) local _, n = reaper.TrackFX_GetFXName(tr, i, ""); return n end
local function resolve_fx(tr, fx)
  if type(fx) == "number" then return fx end
  local want = tostring(fx):lower()
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    if fx_name(tr, i):lower():find(want, 1, true) then return i end
  end
  error("FX not on track: " .. tostring(fx), 3)
end
local function resolve_param(tr, fxi, p)
  if type(p) == "number" then return p end
  local want, sub = tostring(p):lower(), nil
  for i = 0, reaper.TrackFX_GetNumParams(tr, fxi) - 1 do
    local _, n = reaper.TrackFX_GetParamName(tr, fxi, i, "")
    n = n:lower()
    if n == want then return i end
    if not sub and n:find(want, 1, true) then sub = i end
  end
  if sub then return sub end
  error("param not found: " .. tostring(p), 3)
end
H.resolve_fx, H.resolve_param = resolve_fx, resolve_param
function H.installed_fx(filter)
  local out, i = {}, 0
  while true do
    local ok, name = reaper.EnumInstalledFX(i)
    if not ok then break end
    if not filter or name:lower():find(tostring(filter):lower(), 1, true) then out[#out + 1] = name end
    i = i + 1
  end
  return out
end
-- adds the FX if not already on the track (o.new = always add another); returns 0-based index
function H.fx(track, name, o)
  local tr = need_track(track)
  local idx = reaper.TrackFX_AddByName(tr, name, false, (o and o.new) and -1 or 1)
  if idx < 0 then error("FX not found / failed to load: " .. name, 2) end
  return idx
end
function H.clear_fx(track)
  local tr = need_track(track)
  while reaper.TrackFX_GetCount(tr) > 0 do reaper.TrackFX_Delete(tr, 0) end
end
function H.fx_list(track)
  local tr = need_track(track)
  local out = {}
  for i = 0, reaper.TrackFX_GetCount(tr) - 1 do
    out[#out + 1] = { i = i, name = fx_name(tr, i), enabled = reaper.TrackFX_GetEnabled(tr, i) }
  end
  return out
end
function H.params(track, fx, filter)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local out = {}
  for i = 0, reaper.TrackFX_GetNumParams(tr, fxi) - 1 do
    local _, pname = reaper.TrackFX_GetParamName(tr, fxi, i, "")
    if not filter or pname:lower():find(tostring(filter):lower(), 1, true) then
      local _, f = reaper.TrackFX_GetFormattedParamValue(tr, fxi, i, "")
      out[#out + 1] = { i = i, name = pname, v = round(reaper.TrackFX_GetParamNormalized(tr, fxi, i), 4), fmt = f }
    end
  end
  return out
end
-- value is normalized 0..1; returns the plugin's display string
function H.set_param(track, fx, param, value)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  reaper.TrackFX_SetParamNormalized(tr, fxi, pi, value)
  return select(2, reaper.TrackFX_GetFormattedParamValue(tr, fxi, pi, ""))
end
-- parse a plugin display string to a comparable number:
-- "-inf" -> -1e12, "1.2 kHz" -> 1200, "1.50 s" -> 1500 (times compare in ms)
function H.parse_display(f)
  local lf = tostring(f):lower()
  if lf:match("^%s*%-inf") then return -1e12 end
  if lf:match("^%s*%+?inf") then return 1e12 end
  local num = tonumber(lf:match("[-+]?%d*%.?%d+"))
  if not num then return nil end
  if lf:match("[%d%.]%s*k") then return num * 1000 end
  if lf:match("[%d%.]%s*s%s*$") or lf:match("[%d%.]%s*sec") then return num * 1000 end
  return num
end
-- set by displayed value (binary search, assumes monotonic display)
function H.set_param_display(track, fx, param, target)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local function at(v)
    reaper.TrackFX_SetParamNormalized(tr, fxi, pi, v)
    local _, f = reaper.TrackFX_GetFormattedParamValue(tr, fxi, pi, "")
    return H.parse_display(f), f
  end
  local vlo, vhi = at(0), at(1)
  if not vlo or not vhi then error("param display is not numeric: " .. tostring(param), 2) end
  local inc = vhi >= vlo
  local lo, hi = 0, 1
  for _ = 1, 40 do
    local mid = (lo + hi) / 2
    local vm = at(mid)
    if not vm then break end
    if (vm < target) == inc then lo = mid else hi = mid end
  end
  return select(2, at((lo + hi) / 2))
end
-- set an enum/switch param by its displayed label ("On", "LP 24 dB", "Sine")
function H.set_param_choice(track, fx, param, label)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local want = tostring(label):lower()
  local seen, partial = {}, nil
  for s = 0, 200 do
    local v = s / 200
    reaper.TrackFX_SetParamNormalized(tr, fxi, pi, v)
    local _, f = reaper.TrackFX_GetFormattedParamValue(tr, fxi, pi, "")
    local lf = f:lower()
    if lf == want then return f end
    if not partial and lf:find(want, 1, true) then partial = v end
    if seen[#seen] ~= f then seen[#seen + 1] = f end
  end
  if partial then
    reaper.TrackFX_SetParamNormalized(tr, fxi, pi, partial)
    return select(2, reaper.TrackFX_GetFormattedParamValue(tr, fxi, pi, ""))
  end
  error("no choice '" .. tostring(label) .. "'; options: " .. table.concat(seen, ", "), 2)
end
-- list the labels of an enum param
function H.param_choices(track, fx, param)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local keep = reaper.TrackFX_GetParamNormalized(tr, fxi, pi)
  local seen = {}
  for s = 0, 200 do
    reaper.TrackFX_SetParamNormalized(tr, fxi, pi, s / 200)
    local _, f = reaper.TrackFX_GetFormattedParamValue(tr, fxi, pi, "")
    if seen[#seen] ~= f then seen[#seen + 1] = f end
  end
  reaper.TrackFX_SetParamNormalized(tr, fxi, pi, keep)
  return seen
end
-- number -> by displayed value, string -> by choice label
function H.set(track, fx, param, value)
  if type(value) == "number" then return H.set_param_display(track, fx, param, value) end
  return H.set_param_choice(track, fx, param, value)
end

---------------------------------------------------------------- automation
-- FX envelopes store NATIVE values (not normalized). Use automate_display unless you
-- already have native values. shape: 0 linear 1 square 2 slow 3 fast-start 4 fast-end 5 bezier
-- points: {{bar, native_value, shape?}, ...}
function H.automate_native(track, fx, param, points, o)
  o = o or {}
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local env = reaper.GetFXEnvelope(tr, fxi, pi, true)
  if o.clear ~= false then reaper.DeleteEnvelopePointRange(env, -1, 1e9) end
  for _, pt in ipairs(points) do
    reaper.InsertEnvelopePoint(env, H.bar_time(pt[1]), pt[2], pt[3] or o.shape or 0, 0, false, true)
  end
  reaper.Envelope_SortPoints(env)
  return env
end
-- points: {{bar, display_value, shape?}, ...} e.g. {{1, -22}, {18, 0}} for a dB param.
-- Returns the evaluated envelope value at each point (native units) for checking.
function H.automate_display(track, fx, param, points, o)
  o = o or {}
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local keep = reaper.TrackFX_GetParamNormalized(tr, fxi, pi)
  local nat = {}
  for i, pt in ipairs(points) do
    H.set(tr, fxi, pi, pt[2])
    nat[i] = { pt[1], (reaper.TrackFX_GetParam(tr, fxi, pi)), pt[3] }
  end
  reaper.TrackFX_SetParamNormalized(tr, fxi, pi, keep)
  local env = H.automate_native(tr, fxi, pi, nat, o)
  local check = {}
  for _, pt in ipairs(points) do
    local _, v = reaper.Envelope_Evaluate(env, H.bar_time(pt[1]), 44100, 0)
    check[#check + 1] = round(v, 3)
  end
  return check
end
-- deprecated: normalized values are wrong for non-linear params; kept for old cmds
function H.automate(track, fx, param, points, o)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local _, mn, mx = reaper.TrackFX_GetParam(tr, fxi, pi)
  local nat = {}
  for i, pt in ipairs(points) do nat[i] = { pt[1], mn + pt[2] * (mx - mn), pt[3] } end
  H.automate_native(tr, fxi, pi, nat, o)
  return #points
end
-- evaluate an FX param envelope at bars (native units)
function H.envelope_values(track, fx, param, bars)
  local tr = need_track(track)
  local fxi = resolve_fx(tr, fx)
  local pi = resolve_param(tr, fxi, param)
  local env = reaper.GetFXEnvelope(tr, fxi, pi, false)
  if not env then return nil end
  local out = {}
  for i, b in ipairs(bars) do out[i] = round(select(2, reaper.Envelope_Evaluate(env, H.bar_time(b), 44100, 0)), 3) end
  return out
end

---------------------------------------------------------------- markers / transport
function H.region(name, start_bar, end_bar, color)
  return reaper.AddProjectMarker2(0, true, H.bar_time(start_bar), H.bar_time(end_bar), name, -1, color and native_color(color) or 0)
end
function H.marker(name, bar, color)
  return reaper.AddProjectMarker2(0, false, H.bar_time(bar), 0, name, -1, color and native_color(color) or 0)
end
function H.clear_markers()
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = nm + nr - 1, 0, -1 do reaper.DeleteProjectMarkerByIndex(0, i) end
end
function H.cursor(bar) reaper.SetEditCurPos(H.bar_time(bar), true, false) end
function H.play(bar) if bar then H.cursor(bar) end reaper.OnPlayButton() end
function H.stop() reaper.OnStopButton() end

---------------------------------------------------------------- project / render
function H.project_file() return select(2, reaper.EnumProjects(-1)) end
function H.project_dir()
  local fn = H.project_file()
  if fn and fn ~= "" then return fn:match("^(.*[\\/])") end
  return reaper.GetProjectPath() .. "\\"
end
-- saves to the project's own file; refuses on an never-saved project (that would open a dialog)
function H.save()
  local fn = H.project_file()
  if not fn or fn == "" then error("project has never been saved; ask the user to save it first (a Save As dialog would block the bridge)", 2) end
  reaper.Main_SaveProject(0, false)
  return fn
end
-- render master mix to <dir>/<name>.wav (24-bit, 44.1 kHz, stereo). Replaces an existing file
-- (REAPER silently skips rendering if the file exists). o: start_bar, end_bar, tail (s), dir
function H.render(name, o)
  o = o or {}
  if not tostring(name):match("^[%w%-_%.]+$") then error("render name must be [A-Za-z0-9-_.]", 2) end
  local dir = o.dir or (H.project_dir() .. "renders")
  dir = dir:gsub("[\\/]+$", "")
  reaper.RecursiveCreateDirectory(dir, 0)
  local path = dir .. "\\" .. name .. ".wav"
  local replaced = os.remove(path) and true or false
  local t0 = o.start_bar and H.bar_time(o.start_bar) or 0
  local t1 = (o.end_bar and H.bar_time(o.end_bar) or reaper.GetProjectLength(0)) + (o.tail or 2)
  reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true)
  reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", t0, true)
  reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", t1, true)
  reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
  reaper.GetSetProjectInfo(0, "RENDER_SRATE", 44100, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", name, true)
  reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAA==", true) -- WAV 24-bit
  reaper.Main_OnCommand(42230, 0) -- render with current settings, auto-close dialog
  local f = io.open(path, "rb")
  local size = f and f:seek("end") or 0
  if f then f:close() end
  if size == 0 then error("render produced no file: " .. path, 2) end
  return { path = path, size = size, seconds = round(t1 - t0, 3), replaced = replaced }
end

-- project snapshot; o.notes = true includes every note, o.sends = true includes sends
function H.dump(o)
  o = o or {}
  local num, den, bpm = reaper.TimeMap_GetTimeSigAtTime(0, 0)
  local d = {
    tempo = round(bpm, 3), timesig = string.format("%d/%d", num, den),
    length_bars = H.time_bar(reaper.GetProjectLength(0)),
    cursor_bar = H.time_bar(reaper.GetCursorPosition()),
    project = H.project_file(), tracks = {}, regions = {}, markers = {},
  }
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, name = reaper.GetTrackName(tr)
    local t = {
      n = i + 1, name = name,
      vol_db = round(H.vol2db(reaper.GetMediaTrackInfo_Value(tr, "D_VOL")), 2),
      pan = round(reaper.GetMediaTrackInfo_Value(tr, "D_PAN"), 2),
      mute = reaper.GetMediaTrackInfo_Value(tr, "B_MUTE") == 1,
      solo = reaper.GetMediaTrackInfo_Value(tr, "I_SOLO") > 0,
      master_send = reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND") == 1,
      fx = {}, items = {},
    }
    for f = 0, reaper.TrackFX_GetCount(tr) - 1 do
      t.fx[#t.fx + 1] = fx_name(tr, f) .. (reaper.TrackFX_GetEnabled(tr, f) and "" or " [off]")
    end
    if o.sends then t.sends = H.sends(tr) end
    for _, it in ipairs(H.items(tr)) do
      local e = { start_bar = it.start_bar, end_bar = it.end_bar, name = it.name, midi = it.midi }
      if it.midi then
        local _, c = reaper.MIDI_CountEvts(it.take)
        e.notes = c
        if o.notes then e.note_list = H.get_notes(it.take) end
      end
      t.items[#t.items + 1] = e
    end
    d.tracks[#d.tracks + 1] = t
  end
  local _, nm, nr = reaper.CountProjectMarkers(0)
  for i = 0, nm + nr - 1 do
    local _, isrgn, pos, rend, name, idx = reaper.EnumProjectMarkers(i)
    if isrgn then
      d.regions[#d.regions + 1] = { name = name, start_bar = H.time_bar(pos), end_bar = H.time_bar(rend), idx = idx }
    else
      d.markers[#d.markers + 1] = { name = name, bar = H.time_bar(pos), idx = idx }
    end
  end
  return d
end

return H
