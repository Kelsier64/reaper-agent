-- render whole song (plus tail) to renders/<NAME>.wav ; set NAME / END_BAR / TAIL below
local NAME, END_BAR, TAIL = "FurElise_GarbageTruck_v2", 34, 2.5
local dir = [[C:\Users\evan4\Projects\reaper-agent\renders]]
reaper.RecursiveCreateDirectory(dir, 0)
os.remove(dir .. "\\" .. NAME .. ".wav") -- REAPER silently skips if the file already exists
reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 0, true)      -- master mix
reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 0, true)    -- custom time range
reaper.GetSetProjectInfo(0, "RENDER_STARTPOS", 0, true)
reaper.GetSetProjectInfo(0, "RENDER_ENDPOS", H.bar_time(END_BAR) + TAIL, true)
reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
reaper.GetSetProjectInfo(0, "RENDER_SRATE", 44100, true)
reaper.GetSetProjectInfo_String(0, "RENDER_FILE", dir, true)
reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", NAME, true)
reaper.GetSetProjectInfo_String(0, "RENDER_FORMAT", "ZXZhdxgAAA==", true) -- WAV 24-bit
reaper.Main_OnCommand(42230, 0) -- render using most recent settings, auto-close dialog
reaper.Main_SaveProject(0, false)
local f = io.open(dir .. "\\" .. NAME .. ".wav", "rb")
local size = f and f:seek("end") or 0
if f then f:close() end
return { file = NAME .. ".wav", size = size, seconds = H.bar_time(END_BAR) + TAIL }
