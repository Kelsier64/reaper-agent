-- 4-bar test: Fm7 - Dbmaj7 - Ab - Eb on ReaSynth, 90 BPM
H.set_tempo(90)
local tr = H.get_or_add_track("Claude Test Pad", { color = "#7A5CFF", vol_db = -8 })
H.fx(tr, "ReaSynth")
H.set_param(tr, "ReaSynth", "Attack", 0.35)
H.set_param(tr, "ReaSynth", "Release", 0.45)

local take = H.midi_item(tr, 1, 4, { name = "test chords" })
local prog = { "Fm7", "Dbmaj7", "Ab", "Eb" }
local notes = {}
for i, sym in ipairs(prog) do
  for _, p in ipairs(H.chord(sym, 3)) do
    notes[#notes + 1] = { p, (i - 1) * 4, 3.9, 80 }
  end
end
H.add_notes(take, notes)
H.cursor(1)
return { dump = H.dump(), synth_params = H.params(tr, "ReaSynth") }
