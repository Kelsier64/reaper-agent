local inst = {}
for _, n in ipairs(H.installed_fx()) do
  if n:find("VSTi") or n:find("VST3i") or n:find("AUi") or n:find("CLAPi") or n:lower():find("synth") or n:lower():find("sampler") then
    inst[#inst + 1] = n
  end
end
return {
  version = reaper.GetAppVersion(),
  dump = H.dump(),
  Fm7 = H.chord("Fm7", 3),
  c4 = H.n("C4"),
  instruments = inst,
  fx_count = #H.installed_fx(),
}
