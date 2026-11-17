-- after the test suite: is the active project still the song, unchanged?
local d = H.dump()
local names = {}
for _, t in ipairs(d.tracks) do names[#names + 1] = t.name .. "(" .. #t.items .. ")" end
local tabs, i = {}, 0
while true do
  local p, fn = reaper.EnumProjects(i)
  if not p then break end
  tabs[#tabs + 1] = fn
  i = i + 1
end
return { project = d.project, tempo = d.tempo, timesig = d.timesig, tracks = table.concat(names, ", "),
         regions = #d.regions, dirty = reaper.IsProjectDirty(0), tabs = tabs }
