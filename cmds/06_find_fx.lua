local out = {}
for _, n in ipairs(H.installed_fx()) do
  local l = n:lower()
  if l:find("pass") or l:find("eq") or l:find("satur") or l:find("dist") or l:find("verb")
     or l:find("delay") or l:find("filter") or l:find("bit") or l:find("comp") or l:find("limit") then
    out[#out + 1] = n
  end
end
return out
