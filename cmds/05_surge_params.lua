-- load Surge XT on Melody and list its parameters (scene A + global only, to keep it short)
local tr = H.get_or_add_track("Melody")
local fx = H.fx(tr, "Surge XT")
local total = reaper.TrackFX_GetNumParams(tr, fx)
local out = {}
for _, p in ipairs(H.params(tr, fx)) do
  if not p.name:match("^B ") and not p.name:match("^MIDI CC") and not p.name:match("^CC ") then
    out[#out + 1] = p.i .. "|" .. p.name .. "|" .. p.fmt
  end
end
return { fx_name = select(2, reaper.TrackFX_GetFXName(tr, fx, "")), total = total, params = out }
