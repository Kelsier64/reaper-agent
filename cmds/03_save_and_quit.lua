-- save the project into the project folder, then quit REAPER (after this reply is sent)
local path = [[C:\Users\evan4\Projects\reaper-agent\FurElise_GarbageTruck.rpp]]
reaper.Main_SaveProjectEx(0, path, 0)
reaper.defer(function() reaper.Main_OnCommand(40004, 0) end) -- File: Quit REAPER
return { saved = select(2, reaper.EnumProjects(-1)) }
