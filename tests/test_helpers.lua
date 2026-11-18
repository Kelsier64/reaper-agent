-- tests/test_helpers.lua - runs INSIDE REAPER via the bridge (send with -ReadOnly).
-- Opens a throw-away project in a NEW TAB (tests/tmp/run.rpp, copied from fixtures/empty.rpp
-- by run-tests.ps1), runs every test there, saves it (so closing the tab can't prompt), closes
-- the tab and re-selects the user's project. The user's song is never touched.
local TMP = [[__TMP_DIR__]]
local orig_proj = reaper.EnumProjects(-1)
local results = {}

local function fail(msg) error(msg, 0) end
local function eq(a, b, what)
  if a ~= b then fail((what or "value") .. ": expected " .. H.encode(b) .. ", got " .. H.encode(a)) end
end
local function near(a, b, tol, what)
  if type(a) ~= "number" or math.abs(a - b) > (tol or 1e-3) then
    fail((what or "value") .. ": expected ~" .. tostring(b) .. ", got " .. tostring(a))
  end
end
local function truthy(v, what) if not v then fail((what or "condition") .. " is false") end end
local function errors(fn, pattern, what)
  local ok, err = pcall(fn)
  if ok then fail((what or "call") .. " should have raised an error") end
  if pattern and not tostring(err):find(pattern, 1, true) then
    fail((what or "call") .. ": error '" .. tostring(err) .. "' lacks '" .. pattern .. "'")
  end
end
local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  results[#results + 1] = { name = name, ok = ok, err = (not ok) and tostring(err):gsub("\n%s*%[C%].*", "") or nil }
end

-- ---------------------------------------------------------------- open sandbox tab
reaper.Main_OnCommand(40859, 0) -- New project tab
reaper.Main_openProject("noprompt:" .. TMP .. "\\run.rpp")
local sandbox = reaper.EnumProjects(-1)
local sandbox_ok = sandbox ~= orig_proj and H.project_file():lower():find("run.rpp", 1, true) ~= nil

if not sandbox_ok then
  results[#results + 1] = { name = "sandbox project tab", ok = false, err = "could not open sandbox; got " .. tostring(H.project_file()) }
else
  test("sandbox is isolated", function() eq(reaper.CountTracks(0), 0, "tracks in sandbox") end)

  test("note names", function()
    eq(H.n("C4"), 60); eq(H.n("F#2"), 42); eq(H.n("Eb4"), 63); eq(H.n("a-1"), 9); eq(H.n(61), 61)
    errors(function() H.n("H4") end, "bad note name")
  end)

  test("chords", function()
    eq(H.encode(H.chord("Fm7", 3)), "[53,56,60,63]")
    eq(H.encode(H.chord("E5", 3)), "[52,59]")
    eq(H.encode(H.chord("C#maj7", 4)), "[61,65,68,72]")
    errors(function() H.chord("Cxyz") end, "unknown chord")
  end)

  test("tempo / bars 4/4 and 3/8", function()
    H.set_tempo(120, 4, 4)
    near(H.bar_qn(2), 4, 1e-6, "bar 2 qn in 4/4"); near(H.bar_time(2), 2.0, 1e-6, "bar 2 time")
    near(H.time_bar(H.bar_time(3.5)), 3.5, 1e-3, "time_bar roundtrip")
    H.set_tempo(75, 3, 8)
    near(H.bar_qn(2), 1.5, 1e-6, "bar 2 qn in 3/8"); near(H.bar_time(2), 1.2, 1e-6, "bar 2 time @75")
    H.set_tempo(120, 4, 4)
  end)

  test("tracks, unicode names, mix, color", function()
    local tr = H.add_track("測試軌 ü", { vol_db = -6, pan = -0.5, color = "#FF8800" })
    eq(H.track("測試軌 ü"), tr, "find by unicode name")
    eq(H.track(1), tr, "find by index")
    eq(H.get_or_add_track("測試軌 ü"), tr, "get_or_add returns existing")
    near(H.vol2db(reaper.GetMediaTrackInfo_Value(tr, "D_VOL")), -6, 1e-6, "vol")
    near(reaper.GetMediaTrackInfo_Value(tr, "D_PAN"), -0.5, 1e-6, "pan")
    truthy(reaper.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR") ~= 0, "color set")
    H.mix(tr, { mute = true, master_send = false })
    eq(reaper.GetMediaTrackInfo_Value(tr, "B_MUTE"), 1.0, "mute")
    eq(reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND"), 0.0, "master send off")
    errors(function() H.mix("no such track", {}) end, "track not found")
    H.delete_track(tr)
    eq(H.track("測試軌 ü"), nil, "deleted")
  end)

  test("MIDI items and notes roundtrip", function()
    H.set_tempo(90, 4, 4)
    local tr = H.add_track("midi")
    local take = H.midi_item(tr, 2, 2, { name = "clip" })
    eq(H.add_notes(take, { { "C4", 0, 1, 90 }, { p = "E4", s = 1.5, l = 0.5, v = 127.6 }, { 67, 7.75, 0.25 } }), 3)
    local ns = H.get_notes(take)
    eq(#ns, 3, "note count")
    eq(ns[1].p, 60); near(ns[1].s, 0); near(ns[1].l, 1); eq(ns[1].v, 90)
    eq(ns[2].p, 64); near(ns[2].s, 1.5); near(ns[2].l, 0.5); eq(ns[2].v, 127, "velocity clamped")
    eq(ns[3].p, 67); near(ns[3].s, 7.75); eq(ns[3].v, 100, "default velocity")
    local it = H.items(tr)[1]
    near(it.start_bar, 2); near(it.end_bar, 4); eq(it.name, "clip"); eq(it.midi, true)
    eq(H.take(tr, 1), take, "H.take")
    H.clear_notes(take); eq(#H.get_notes(take), 0, "cleared")
    H.midi_item(tr, 6, 1)
    eq(H.delete_items(tr, 5, 10), 1, "delete in range"); eq(#H.items(tr), 1)
    eq(H.delete_items(tr), 1, "delete all")
    H.delete_track(tr)
  end)

  test("sends: ensure_send is idempotent", function()
    local a, b = H.add_track("src"), H.add_track("bus")
    H.ensure_send(a, b, -6); H.ensure_send(a, b, -3)
    eq(reaper.GetTrackNumSends(a, 0), 1, "one send")
    near(H.sends(a)[1].vol_db, -3, 0.01, "send level updated"); eq(H.sends(a)[1].dest, "bus")
    H.delete_track(a); H.delete_track(b)
  end)

  test("FX params: display values, -inf, choices", function()
    local tr = H.add_track("fx")
    local eqi = H.fx(tr, "ReaEQ")
    eq(H.fx(tr, "ReaEQ"), eqi, "fx() reuses existing instance")
    eq(H.fx(tr, "ReaEQ", { new = true }), eqi + 1, "fx(new) adds another")
    local f = H.set(tr, eqi, "Freq-Band 3", 1234)
    near(H.parse_display(f), 1234, 2, "freq by display")
    eq(H.set(tr, eqi, "Gain-Low Shelf", -200), "-inf", "-inf reachable")
    local bw = H.fx(tr, "JS: Butterworth 4-Pole Filter", { new = true })
    eq(H.set(tr, bw, "Filter Type", "HP"), "HP", "choice by label")
    truthy(#H.param_choices(tr, bw, "Filter Type") >= 2, "param_choices lists options")
    errors(function() H.set(tr, bw, "Filter Type", "nope") end, "options:")
    errors(function() H.set(tr, eqi, "no such param", 1) end, "param not found")
    errors(function() H.fx(tr, "Definitely Not A Plugin 123") end, "FX not found")
    eq(#H.fx_list(tr), 3, "fx_list")
    H.clear_fx(tr); eq(reaper.TrackFX_GetCount(tr), 0, "clear_fx")
    H.delete_track(tr)
  end)

  test("parse_display units", function()
    eq(H.parse_display("-inf"), -1e12); eq(H.parse_display("1.50 s"), 1500); eq(H.parse_display("250.0 ms"), 250)
    eq(H.parse_display("1.2 kHz"), 1200); eq(H.parse_display("-6.0 dB"), -6); eq(H.parse_display("Off"), nil)
  end)

  test("automate_display writes native values", function()
    local tr = H.add_track("auto")
    local vp = H.fx(tr, "JS: Volume/Pan Adjustment (Cockos)")
    local chk = H.automate_display(tr, vp, "Volume (dB)", { { 1, -22 }, { 3, 0 }, { 5, 6 } })
    near(chk[1].native, -22, 0.2, "vol @1"); near(chk[2].native, 0, 0.2, "vol @3"); near(chk[3].native, 6, 0.2, "vol @5")
    eq(chk[1].bar, 1, "record bar"); eq(chk[1].want, -22, "record want")
    near(H.parse_display(chk[1].display), -22, 0.2, "record display")
    local p = H.automate_display(tr, vp, "Pan", { { 1, -60 }, { 2, 40 } })
    near(p[1].native, -60, 0.5, "pan @1"); near(p[2].native, 40, 0.5, "pan @2")
    near(H.envelope_values(tr, vp, "Volume (dB)", { 2 })[1], -11, 0.5, "linear midpoint")
    H.delete_track(tr)
  end)

  test("Surge XT seconds display (skipped if not installed)", function()
    if #H.installed_fx("Surge XT") == 0 then return end
    local tr = H.add_track("surge")
    local s = H.fx(tr, "Surge XT")
    eq(H.set(tr, s, "A Amp EG Decay", 1500), "1.50 s", "decay 1.5 s")
    eq(H.set(tr, s, "A Amp EG Release", 90), "90.0 ms", "release 90 ms")
    eq(H.set(tr, s, "A Osc 1 Type", "Sine"), "Sine", "osc type")
    H.delete_track(tr)
  end)

  test("regions / markers / dump", function()
    H.clear_markers()
    H.region("Intro", 1, 3, "#888888"); H.marker("hit", 2)
    local d = H.dump({ sends = true })
    eq(#d.regions, 1); eq(d.regions[1].name, "Intro"); near(d.regions[1].end_bar, 3)
    eq(#d.markers, 1); near(d.markers[1].bar, 2)
    eq(d.timesig, "4/4"); truthy(d.project:lower():find("run.rpp", 1, true), "dump.project")
    H.clear_markers(); eq(#H.dump().regions, 0, "clear_markers")
  end)

  test("render writes and replaces a file", function()
    local tr = H.add_track("synth")
    H.fx(tr, "ReaSynth")
    H.add_notes(H.midi_item(tr, 1, 1), { { "A4", 0, 2, 100 } })
    local r1 = H.render("helpers_test", { dir = TMP, end_bar = 2, tail = 0.5 })
    truthy(r1.size > 100000, "render size " .. r1.size)
    near(r1.seconds, H.bar_time(2) + 0.5, 0.01, "render length (bar 2 + tail)")
    local f = io.open(r1.path, "rb"); local size = f:seek("end"); f:close()
    near(size, r1.seconds * 44100 * 2 * 3, 44100 * 6 * 0.05, "file size matches 24-bit stereo length")
    local r2 = H.render("helpers_test", { dir = TMP, end_bar = 2, tail = 0.5 })
    eq(r2.replaced, true, "second render replaced the file")
    errors(function() H.render("bad name!", {}) end, "render name")
    H.delete_track(tr)
  end)

  test("render restores the project's render settings and dirty state", function()
    local tr = H.add_track("synth2")
    H.fx(tr, "ReaSynth")
    H.add_notes(H.midi_item(tr, 1, 1), { { "C4", 0, 1, 100 } })
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", [[C:\keep\me]], true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "user_pattern", true)
    reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 12.5, true)
    reaper.Main_SaveProject(0, false)
    eq(reaper.IsProjectDirty(0), 0, "clean before render")
    local r = H.render("helpers_settings", { dir = TMP, end_bar = 2, tail = 0 })
    local _, file = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
    local _, pat = reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", false)
    eq(file, [[C:\keep\me]], "RENDER_FILE restored"); eq(pat, "user_pattern", "RENDER_PATTERN restored")
    near(reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 0, false), 12.5, 1e-6, "RENDER_ENDPOS restored")
    eq(reaper.IsProjectDirty(0), 0, "clean project stays clean"); eq(r.saved_project, true, "saved_project")
    -- unsaved changes are never saved for the user
    H.mix(tr, { vol_db = -3 })
    reaper.MarkProjectDirty(0)
    local r2 = H.render("helpers_settings", { dir = TMP, end_bar = 2, tail = 0 })
    eq(r2.saved_project, false, "dirty project not saved")
    truthy(reaper.IsProjectDirty(0) ~= 0, "dirty project stays dirty")
    H.delete_track(tr)
  end)

  test("automate_display reports display values for non-dB native units (ReaEQ)", function()
    local tr = H.add_track("eqauto")
    local eqi = H.fx(tr, "ReaEQ")
    local chk = H.automate_display(tr, eqi, "Gain-Band 2", { { 1, -6 }, { 3, 3 } })
    near(H.parse_display(chk[1].display), -6, 0.15, "display @1"); near(H.parse_display(chk[2].display), 3, 0.15, "display @3")
    truthy(math.abs(chk[1].native - (-6)) > 1, "native is not dB for ReaEQ gain (" .. chk[1].native .. ")")
    H.delete_track(tr)
  end)

  test("params filter: substring and ^prefix", function()
    local tr = H.add_track("pf")
    local eqi = H.fx(tr, "ReaEQ")
    local sub = H.params(tr, eqi, "band 2")
    truthy(#sub >= 3, "substring finds Freq/Gain/BW-Band 2")
    local pre = H.params(tr, eqi, "^gain")
    truthy(#pre >= 1, "prefix finds Gain-*")
    for _, p in ipairs(pre) do truthy(p.name:lower():sub(1, 4) == "gain", "prefix only: " .. p.name) end
    eq(#H.params(tr, eqi, "^band"), 0, "^band matches nothing (names start with Freq/Gain/BW)")
    H.delete_track(tr)
  end)

  test("require_project guards the active tab", function()
    truthy(H.require_project("run.rpp"):lower():find("run.rpp", 1, true), "matches sandbox")
    truthy(H.require_project("RUN"), "case-insensitive")
    errors(function() H.require_project("SomeOtherSong") end, "active project is run.rpp")
  end)

  test("render srate/channels: 48 kHz mono", function()
    local tr = H.add_track("mono")
    H.fx(tr, "ReaSynth")
    H.add_notes(H.midi_item(tr, 1, 1), { { "A4", 0, 1, 100 } })
    local r = H.render("helpers_mono48", { dir = TMP, end_bar = 2, tail = 0, srate = 48000, channels = 1 })
    eq(r.srate, 48000, "srate"); eq(r.channels, 1, "channels")
    local f = io.open(r.path, "rb"); local hdr = f:read(44); f:close()
    eq(string.unpack("<I2", hdr, 23), 1, "WAV channels"); eq(string.unpack("<I4", hdr, 25), 48000, "WAV sample rate")
    errors(function() H.render("x", { channels = 6 }) end, "channels must be 1 or 2")
    H.delete_track(tr)
  end)

  test("listen sets loop, cursor, view and selection without dirtying", function()
    local a = H.add_track("listen A"); local b = H.add_track("listen B")
    H.add_notes(H.midi_item(a, 1, 8), { { "C4", 0, 1, 90 } })
    reaper.Main_SaveProject(0, false)
    local r = H.listen({ from_bar = 2, to_bar = 4, tracks = { "listen B" } })
    local ls, le = reaper.GetSet_LoopTimeRange2(0, false, true, 0, 0, false)
    near(ls, H.bar_time(2), 1e-6, "loop start"); near(le, H.bar_time(4), 1e-6, "loop end")
    near(reaper.GetCursorPosition(), H.bar_time(2), 1e-6, "cursor")
    eq(reaper.GetSetRepeat(-1), 1, "repeat on")
    eq(reaper.IsTrackSelected(b), true, "B selected"); eq(reaper.IsTrackSelected(a), false, "A not selected")
    eq(r.tracks[1], "listen B", "reported tracks"); eq(r.playing, false, "not playing")
    eq(reaper.IsProjectDirty(0), 0, "clean project stays clean")
    errors(function() H.listen({ from_bar = 4, to_bar = 2 }) end, "to_bar must be after")
    reaper.GetSetRepeat(0)
    H.delete_track(a); H.delete_track(b)
  end)

  test("dump includes the master track", function()
    local d = H.dump()
    truthy(d.master and type(d.master.vol_db) == "number" and type(d.master.fx) == "table", "master in dump")
  end)

  test("save() writes the project's own file", function()
    eq(H.save():lower():find("run.rpp", 1, true) ~= nil, true, "save() saves the sandbox file")
  end)

  -- ---------------------------------------------------------------- close sandbox
  reaper.Main_SaveProject(0, false)               -- has a path -> no dialog; leaves it clean
  if reaper.EnumProjects(-1) == sandbox then reaper.Main_OnCommand(40860, 0) end -- Close project tab
end
reaper.SelectProjectInstance(orig_proj)
local passed = 0
for _, r in ipairs(results) do if r.ok then passed = passed + 1 end end
return { passed = passed, failed = #results - passed, results = results,
         back_on_user_project = reaper.EnumProjects(-1) == orig_proj, helpers = H.version }
