-- evaluate Distance envelopes at a few bars + list sends
local dist = H.track("Distance")
local out = { envs = {}, sends = {} }
for e = 0, reaper.CountTrackEnvelopes(dist) - 1 do
  local env = reaper.GetTrackEnvelope(dist, e)
  local _, name = reaper.GetEnvelopeName(env)
  local vals = {}
  for _, bar in ipairs({ 1, 10, 18, 26, 34 }) do
    local _, v = reaper.Envelope_Evaluate(env, H.bar_time(bar), 44100, 0)
    vals[#vals + 1] = bar .. ":" .. H.round(v, 3)
  end
  out.envs[#out.envs + 1] = { name = name, points = reaper.CountEnvelopePoints(env), at = table.concat(vals, "  ") }
end
for _, t in ipairs({ "Loudspeaker", "Bell", "Dusk Pad", "City Ambience", "Melody", "Accomp" }) do
  local tr = H.track(t)
  for i = 0, reaper.GetTrackNumSends(tr, 0) - 1 do
    local dst = reaper.GetTrackSendInfo_Value(tr, 0, i, "P_DESTTRACK")
    local _, dn = reaper.GetTrackName(dst)
    out.sends[#out.sends + 1] = t .. " -> " .. dn .. " " .. H.round(H.vol2db(reaper.GetTrackSendInfo_Value(tr, 0, i, "D_VOL")), 1) .. " dB"
  end
end
local dvp = 1
local _, mn, mx = reaper.TrackFX_GetParam(dist, dvp, 0)
out.vol_range = { mn, mx }
return out
