-- probe: JS Volume/Pan params + Surge XT enum options, on a temp track
local tr = H.add_track("_probe")
local out = {}
local vp = H.fx(tr, "JS: Volume/Pan Adjustment (Cockos)", { new = true })
out.volpan = H.params(tr, vp)
local s = H.fx(tr, "Surge XT", { new = true })
local function options(param)
  local pi
  for _, p in ipairs(H.params(tr, s, param)) do if p.name == param then pi = p.i end end
  local seen = {}
  for st = 0, 200 do
    reaper.TrackFX_SetParamNormalized(tr, s, pi, st / 200)
    local _, f = reaper.TrackFX_GetFormattedParamValue(tr, s, pi, "")
    if seen[#seen] ~= f then seen[#seen + 1] = f end
  end
  return seen
end
for _, p in ipairs({ "A Osc 1 Type", "A Filter 1 Type", "A FM Routing", "A Osc 1 Unison Voices", "A Filter Configuration" }) do
  out[p] = options(p)
end
-- subtype list depends on type: set Lowpass-ish first
reaper.DeleteTrack(tr)
return out
