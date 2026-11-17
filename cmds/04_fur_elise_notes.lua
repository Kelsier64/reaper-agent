-- Für Elise (Beethoven, WoO 59) - opening section A A B A, garbage-truck style
-- 3/8, sixteenth = 0.25 QN, bar = 1.5 QN. Note format inside a bar: {pitch, pos16, len16}

-- remove the earlier test track
local old = H.track("Claude Test Pad")
if old then reaper.DeleteTrack(old) end

H.set_tempo(75, 3, 8)

local LH_A  = { { "A2", 0, 1 }, { "E3", 1, 1 }, { "A3", 2, 1 } }
local LH_E  = { { "E2", 0, 1 }, { "E3", 1, 1 }, { "G#3", 2, 1 } }

local m1 = { rh = { { "E5", 0, 1 }, { "D#5", 1, 1 }, { "E5", 2, 1 }, { "B4", 3, 1 }, { "D5", 4, 1 }, { "C5", 5, 1 } }, lh = {} }
local m2 = { rh = { { "A4", 0, 2 }, { "C4", 3, 1 }, { "E4", 4, 1 }, { "A4", 5, 1 } }, lh = LH_A }
local m3 = { rh = { { "B4", 0, 2 }, { "E4", 3, 1 }, { "G#4", 4, 1 }, { "B4", 5, 1 } }, lh = LH_E }
local m4 = { rh = { { "C5", 0, 2 }, { "E4", 3, 1 }, { "E5", 4, 1 }, { "D#5", 5, 1 } }, lh = LH_A }
local m7 = { rh = { { "B4", 0, 2 }, { "E4", 3, 1 }, { "C5", 4, 1 }, { "B4", 5, 1 } }, lh = LH_E }
local A_BODY = { m1, m2, m3, m4, m1, m2, m7 }

local pickup = { rh = { { "E5", 4, 1 }, { "D#5", 5, 1 } }, lh = {} }
local end1   = { rh = { { "A4", 0, 2 }, { "E5", 4, 1 }, { "D#5", 5, 1 } }, lh = LH_A }
local end2   = { rh = { { "A4", 0, 2 }, { "B4", 3, 1 }, { "C5", 4, 1 }, { "D5", 5, 1 } }, lh = LH_A }
local endF   = { rh = { { "A4", 0, 5 } }, lh = { { "A2", 0, 1 }, { "E3", 1, 1 }, { "A3", 2, 3 } } }

local B = {
  { rh = { { "E5", 0, 3 }, { "G4", 3, 1 }, { "F5", 4, 1 }, { "E5", 5, 1 } }, lh = { { "C3", 0, 1 }, { "G3", 1, 1 }, { "C4", 2, 1 } } },
  { rh = { { "D5", 0, 3 }, { "F4", 3, 1 }, { "E5", 4, 1 }, { "D5", 5, 1 } }, lh = { { "G2", 0, 1 }, { "G3", 1, 1 }, { "B3", 2, 1 } } },
  { rh = { { "C5", 0, 3 }, { "E4", 3, 1 }, { "D5", 4, 1 }, { "C5", 5, 1 } }, lh = LH_A },
  { rh = { { "B4", 0, 2 }, { "E4", 3, 1 }, { "E5", 4, 1 }, { "E4", 5, 1 } }, lh = { { "E2", 0, 1 }, { "E3", 1, 1 } } },
  { rh = { { "E5", 1, 1 }, { "E6", 2, 1 }, { "D#5", 5, 1 } }, lh = {} },
  { rh = { { "E5", 0, 1 }, { "D#5", 1, 1 }, { "E5", 2, 1 }, { "D#5", 3, 1 }, { "E5", 4, 1 }, { "D#5", 5, 1 } }, lh = {} },
}

-- assemble bar list
local bars = { pickup }
local function add(list) for _, b in ipairs(list) do bars[#bars + 1] = b end end
add(A_BODY); add({ end1 })   -- bars 2-9
add(A_BODY); add({ end2 })   -- bars 10-17
add(B)                       -- bars 18-23
add(A_BODY); add({ endF })   -- bars 24-31

local S, BAR, GATE = 0.25, 1.5, 0.92
local function collect(hand, vel)
  local out = {}
  for bi, b in ipairs(bars) do
    for _, nt in ipairs(b[hand]) do
      out[#out + 1] = { nt[1], (bi - 1) * BAR + nt[2] * S, nt[3] * S * GATE, vel }
    end
  end
  return out
end

local melody = H.get_or_add_track("Melody", { color = "#F2C94C" })
local accomp = H.get_or_add_track("Accomp", { color = "#56CCF2" })
H.delete_items(melody); H.delete_items(accomp)
local n = #bars
local t1 = H.midi_item(melody, 1, n + 1, { name = "Für Elise RH" })
local t2 = H.midi_item(accomp, 1, n + 1, { name = "Für Elise LH" })
local c1 = H.add_notes(t1, collect("rh", 100))
local c2 = H.add_notes(t2, collect("lh", 88))

H.clear_markers()
H.region("Pickup", 1, 2, "#888888")
H.region("A", 2, 10, "#F2994A")
H.region("A'", 10, 18, "#F2C94C")
H.region("B", 18, 24, "#6FCF97")
H.region("A''", 24, 32, "#F2994A")
H.cursor(1)
return { bars = n, rh_notes = c1, lh_notes = c2, dump = H.dump() }
