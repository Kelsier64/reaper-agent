-- 18_restore_render_settings: undo what the old H.render (helpers < 2.1.0) left behind after the
-- restore-check render: put the project's render target/range back to the v2 values, then save.
reaper.GetSetProjectInfo_String(0, "RENDER_FILE", [[C:\Users\evan4\Projects\reaper-agent\renders\FurElise_GarbageTruck_v2.wav]], true)
reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "", true)
reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", 0, true)
reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 42.1, true)
H.save()
local _, f = reaper.GetSetProjectInfo_String(0, "RENDER_FILE", "", false)
return { file = f, endpos = reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", 0, false), dirty = reaper.IsProjectDirty(0), helpers = H.version }
