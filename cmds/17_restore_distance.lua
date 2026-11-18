-- 17_restore_distance: put back the "Distance" track that disappeared in the 12:01 save.
-- The chunk is copied verbatim from the last commit (FX, FX envelopes, receive from Loudspeaker).
local chunk = [==[
<TRACK {A3445FF9-6040-4F13-86D8-40F917AAD783}
  NAME Distance
  PEAKCOL 31026107
  BEAT -1
  AUTOMODE 0
  PANLAWFLAGS 3
  VOLPAN 1 0 -1 -1 1
  MUTESOLO 0 0 0
  IPHASE 0
  PLAYOFFS 0 1
  ISBUS 0 0
  BUSCOMP 0 0 0 0 0
  SHOWINMIX 1 0.6667 0.5 1 0.5 0 0 0 0
  FIXEDLANES 9 0 0 0 0
  SEL 0
  REC 0 0 1 0 0 0 0 0
  VU 64
  TRACKHEIGHT 0 0 0 0 0 0 0
  INQ 0 0 0 0.5 100 0 0 100
  NCHAN 2
  FX 1
  TRACKID {A3445FF9-6040-4F13-86D8-40F917AAD783}
  PERF 0
  AUXRECV 3 0 1 0 0 0 0 0 0 -1:U 0 -1 ''
  MIDIOUT -1 -1
  MAINSEND 1 0
  <FXCHAIN
    SHOW 0
    LASTSEL 0
    DOCKED 0
    BYPASS 0 0 0
    <VST "VST: ReaEQ (Cockos)" reaeq.dll 0 "" 1919247729<56535472656571726561657100000000> ""
      cWVlcu5e7f4CAAAAAQAAAAAAAAACAAAAAAAAAAIAAAABAAAAAAAAAAIAAAAAAAAAzQAAAAEAAAAAABAA
      IQAAAAUAAAAAAAAAAQAAAAAAAAAAAFlAAAAAAAAA8D+amZmZmZnpPwEIAAAAAQAAAAAAAAAAwHJAAAAAAAAA8D8AAAAAAAAAQAEIAAAAAQAAAAAAAAAAQI9AAAAAAAAA
      8D8AAAAAAAAAQAEBAAAAAQAAAJWVp3bmh6NAAAAAoJErxD8AAAAgCtfvPwEEAAAAAAAAAAAAAAAAAFlAAAAAAAAA8D8AAAAAAAAAQAEBAAAAAQAAAAAAAAAAAPA/AAAA
      AAAAAAAAAAAAAgABAA==
      AAAQAAAA
    >
    MULTIFXLINK 0
    FLOATPOS 0 0 0 0
    FXID {181BD6B9-9187-431D-A495-E55AC61C9A9F}
    <PARMENV 10:_Gain_High_Shelf_4 0 1 0.25 "Gain-High Shelf 4 / ReaEQ"
      EGUID {95A19869-995D-473A-94AB-00C7F4CA11AE}
      ACT 1 -1
      VIS 1 1 1
      LANEHEIGHT 0 0
      ARM 1
      DEFSHAPE 0 -1 -1
      PT 0 0.04959524 2
      PT 10.8 0.11102992 2
      PT 18 0.19744222 2
      PT 20.4 0.24856503 2
      PT 26.4 0.24856503 2
      PT 30 0.15683393 2
      PT 36 0.07860316 2
      PT 39.6 0.0393949 2
    >
    WAK 0 0
    BYPASS 0 0 0
    <JS utility/volume_pan_sample_accurate_auto ""
      -30 75 0 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    >
    MULTIFXLINK 0
    FLOATPOS 0 0 0 0
    FXID {01C6C388-2977-4864-8206-B381681AA022}
    <PARMENV 0 -60 12 0 "Volume (dB) / Volume/Pan Adjustment"
      EGUID {CDCE81D8-DEF0-4B21-A51F-62ABC7BF6569}
      ACT 1 -1
      VIS 1 1 1
      LANEHEIGHT 0 0
      ARM 1
      DEFSHAPE 0 -1 -1
      PT 0 -22 2
      PT 10.8 -11.1 2
      PT 18 -4.1 2
      PT 20.4 0 2
      PT 26.4 0 2
      PT 30 -6 2
      PT 36 -16.1 2
      PT 39.6 -30 2
    >
    <PARMENV 1 -100 100 0 "Pan / Volume/Pan Adjustment"
      EGUID {F7319FA9-5E41-42AD-B57A-BF946EAB3E04}
      ACT 1 -1
      VIS 1 1 1
      LANEHEIGHT 0 0
      ARM 1
      DEFSHAPE 0 -1 -1
      PT 0 -60 2
      PT 10.8 -35 2
      PT 18 -15.1 2
      PT 20.4 0 2
      PT 26.4 9.9 2
      PT 30 34.9 2
      PT 36 59.9 2
      PT 39.6 75 2
    >
    WAK 0 0
  >
>
]==]
if H.track("Distance") then error("Distance already exists; nothing to restore") end
local _, n4 = reaper.GetTrackName(reaper.GetTrack(0, 3))
if n4 ~= "Loudspeaker" then error("expected track 4 to be Loudspeaker, got " .. tostring(n4)) end
reaper.InsertTrackAtIndex(4, true)
local tr = reaper.GetTrack(0, 4)
if not reaper.SetTrackStateChunk(tr, chunk, false) then error("SetTrackStateChunk failed") end
local recv = {}
for i = 0, reaper.GetTrackNumSends(tr, -1) - 1 do
  local _, src = reaper.GetTrackName(reaper.GetTrackSendInfo_Value(tr, -1, i, "P_SRCTRACK"))
  recv[#recv + 1] = { src = src, vol_db = H.vol2db(reaper.GetTrackSendInfo_Value(tr, -1, i, "D_VOL")) }
end
local envs = {}
for i = 0, reaper.CountTrackEnvelopes(tr) - 1 do
  local env = reaper.GetTrackEnvelope(tr, i)
  local _, en = reaper.GetEnvelopeName(env)
  envs[#envs + 1] = { name = en, points = reaper.CountEnvelopePoints(env) }
end
H.save()
local _, name = reaper.GetTrackName(tr)
return { name = name, index = 5, master_send = reaper.GetMediaTrackInfo_Value(tr, "B_MAINSEND"),
         fx = H.fx_list(tr), receives = recv, envelopes = envs }
