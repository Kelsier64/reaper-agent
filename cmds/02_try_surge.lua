-- see whether REAPER already knows Surge XT; try loading it on a scratch track
local found = H.installed_fx("surge")
local tr = H.get_or_add_track("Surge probe")
local idx = reaper.TrackFX_AddByName(tr, "Surge XT", false, 1)
local name = idx >= 0 and select(2, reaper.TrackFX_GetFXName(tr, idx, "")) or nil
local nparams = idx >= 0 and reaper.TrackFX_GetNumParams(tr, idx) or 0
if idx < 0 then reaper.DeleteTrack(tr) end
return { installed = found, loaded_index = idx, loaded_name = name, nparams = nparams }
