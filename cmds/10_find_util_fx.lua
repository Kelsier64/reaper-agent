local out = {}
for _, n in ipairs(H.installed_fx()) do
  local l = n:lower()
  if l:find("volume") or l:find("pan") or l:find("width") or l:find("stereo") or l:find("chorus") or l:find("utility") then
    out[#out + 1] = n
  end
end
return out
