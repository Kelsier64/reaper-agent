-- load candidate FX on a temporary track, list their params, then remove the track
local tr = H.add_track("_probe")
local names = { "JS: Butterworth 4-Pole Filter", "ReaEQ", "JS: Saturation", "JS: Waveshaping Distortion",
                "ReaDelay", "ReaVerbate", "JS: Master Limiter" }
local out = {}
for _, n in ipairs(names) do
  local i = H.fx(tr, n, { new = true })
  local ps = {}
  for _, p in ipairs(H.params(tr, i)) do
    if p.name ~= "Bypass" and p.name ~= "Wet" and p.name ~= "Delta" then ps[#ps + 1] = p.i .. "|" .. p.name .. "|" .. p.fmt end
  end
  out[n] = ps
end
reaper.DeleteTrack(tr)
return out
