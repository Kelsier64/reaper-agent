-- bridge.lua - REAPER side of the Claude bridge.
-- Loaded by the loader that tools/install.ps1 writes to
--   %APPDATA%\REAPER\Scripts\ClaudeBridge\ClaudeBridge.lua
-- Protocol (one request at a time; clients serialize with a lock file):
--   client writes inbox/request.lua  (header lines: "-- id: X", optional "-- label: ...", "-- readonly")
--   bridge runs it with H (helpers.lua) in scope, writes outbox/response.json:
--   {"id":X,"ok":true|false,"result":...,"error":"...","log":[...],"bridge":ver,"helpers":ver}
-- helpers.lua is re-loaded automatically whenever its content changes.
-- Every non-readonly request is one undo point "Claude: <label>".
-- Running the loader again (Action list) stops the bridge.

local BRIDGE_VERSION = "2.0.0"

local SEP = package.config:sub(1, 1)
local ROOT = CLAUDE_BRIDGE_ROOT or (debug.getinfo(1, "S").source:match("^@(.*[\\/])") or "")
local BASE = reaper.GetResourcePath() .. SEP .. "Scripts" .. SEP .. "ClaudeBridge" .. SEP
local INBOX, OUTBOX = BASE .. "inbox" .. SEP, BASE .. "outbox" .. SEP
reaper.RecursiveCreateDirectory(INBOX, 0)
reaper.RecursiveCreateDirectory(OUTBOX, 0)
local REQ = INBOX .. "request.lua"
local RESP, RESP_TMP = OUTBOX .. "response.json", OUTBOX .. "response.tmp"
local HEARTBEAT, STATUS = BASE .. "heartbeat.txt", BASE .. "status.json"
local HELPERS = ROOT .. "helpers.lua"

---------------------------------------------------------------- io
local function readall(p)
  local f = io.open(p, "rb")
  if not f then return nil end
  local s = f:read("a"); f:close()
  return s
end
local function writeall(p, s)
  local f = assert(io.open(p, "wb"))
  f:write(s); f:close()
end

---------------------------------------------------------------- JSON
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r',
              ['\t'] = '\\t', ['\b'] = '\\b', ['\f'] = '\\f' }
local function jstr(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function encode(v, depth, seen)
  depth = depth or 0
  local t = type(v)
  if v == nil then return "null"
  elseif t == "boolean" then return tostring(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    local i = math.tointeger(v)
    if i then return tostring(i) end
    return string.format("%.10g", v)
  elseif t == "string" then return jstr(v)
  elseif t == "table" then
    if depth > 12 then return '"<max depth>"' end
    seen = seen or {}
    if seen[v] then return '"<cycle>"' end
    seen[v] = true
    local n, count = #v, 0
    for _ in pairs(v) do count = count + 1 end
    local out, s = {}, nil
    if count == n then
      for i = 1, n do out[i] = encode(v[i], depth + 1, seen) end
      s = "[" .. table.concat(out, ",") .. "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, k in ipairs(keys) do
        out[#out + 1] = jstr(tostring(k)) .. ":" .. encode(v[k], depth + 1, seen)
      end
      s = "{" .. table.concat(out, ",") .. "}"
    end
    seen[v] = nil
    return s
  end
  return jstr(tostring(v))
end

---------------------------------------------------------------- helpers (hot reload)
local H, helpers_src, helpers_err = {}, nil, nil
local function load_helpers()
  local src = readall(HELPERS)
  if not src then helpers_err = "helpers.lua not found at " .. HELPERS; return end
  if src == helpers_src then return end
  helpers_src = src -- don't retry a broken file until it changes again
  local chunk, err = load(src, "@" .. HELPERS, "t", _G)
  if not chunk then helpers_err = "helpers compile error (still using previous helpers): " .. tostring(err); return end
  local ok, res = pcall(chunk, { encode = encode, bridge_version = BRIDGE_VERSION })
  if not ok or type(res) ~= "table" then
    helpers_err = "helpers load error (still using previous helpers): " .. tostring(res); return
  end
  res._src_size = #src
  res._loaded_at = os.time()
  H, helpers_err = res, nil
end

---------------------------------------------------------------- requests
local function run_request(code)
  load_helpers()
  local id = code:match("^%-%- id: ([%w%-_]+)") or "?"
  local label = code:match("%-%- label: ([^\r\n]+)") or "edit"
  local readonly = code:match("\n%-%- readonly") ~= nil or code:match("\n%-%- noundo") ~= nil
  local logs = {}
  local env = setmetatable({ H = H, r = reaper }, { __index = _G })
  env.log = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
      local v = select(i, ...)
      parts[#parts + 1] = type(v) == "table" and encode(v) or tostring(v)
    end
    logs[#logs + 1] = table.concat(parts, " ")
  end
  env.print = env.log
  local base = { id = id, bridge = BRIDGE_VERSION, helpers = H.version, helpers_error = helpers_err, log = logs }
  local chunk, err = load(code, "=request", "t", env)
  if not chunk then
    base.ok, base.error = false, "compile: " .. tostring(err)
    return encode(base)
  end
  if not readonly then reaper.Undo_BeginBlock2(0) end
  reaper.PreventUIRefresh(1)
  local res = table.pack(xpcall(chunk, debug.traceback))
  reaper.PreventUIRefresh(-1)
  reaper.UpdateArrange()
  reaper.UpdateTimeline()
  if not readonly then reaper.Undo_EndBlock2(0, "Claude: " .. label, -1) end
  if res[1] then base.ok, base.result = true, res[2]
  else base.ok, base.error = false, tostring(res[2]) end
  return encode(base)
end

local function write_status()
  local _, proj = reaper.EnumProjects(-1)
  writeall(STATUS, encode({
    time = os.time(), bridge = BRIDGE_VERSION, helpers = H.version, helpers_error = helpers_err,
    root = ROOT, project = proj, play_state = reaper.GetPlayState(), reaper = reaper.GetAppVersion(),
  }))
  writeall(HEARTBEAT, tostring(os.time()))
end

local last_poll, last_hb = 0, 0
local function tick()
  local now = reaper.time_precise()
  if now - last_poll >= 0.05 then
    last_poll = now
    local code = readall(REQ)
    if code then
      os.remove(REQ)
      local ok, out = pcall(run_request, code)
      if not ok then
        out = encode({ id = code:match("^%-%- id: ([%w%-_]+)") or "?", ok = false, error = "bridge: " .. tostring(out) })
      end
      os.remove(RESP)
      writeall(RESP_TMP, out)
      os.rename(RESP_TMP, RESP)
      last_hb = 0 -- refresh heartbeat right after a (possibly long) request
    end
    if now - last_hb >= 2 then
      pcall(write_status)
      last_hb = now
    end
  end
  reaper.defer(tick)
end

load_helpers()
local _, _, sec, cmd = reaper.get_action_context()
if reaper.set_action_options then reaper.set_action_options(1) end -- re-run = stop
if cmd and cmd > 0 then
  reaper.SetToggleCommandState(sec, cmd, 1)
  reaper.RefreshToolbar2(sec, cmd)
end
reaper.atexit(function()
  if cmd and cmd > 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
  end
  os.remove(HEARTBEAT)
  os.remove(STATUS)
end)
os.remove(REQ)
tick()
