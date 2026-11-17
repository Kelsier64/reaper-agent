# tests/test_protocol.ps1 - client <-> bridge protocol tests (needs a running bridge).
# Read-only requests only, except the hot-reload test which edits bridge\helpers.lua and restores it.
# Prints PASS/FAIL lines; exit code = number of failures.
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$send = Join-Path $root 'tools\send.ps1'
$tmp = Join-Path $root 'tests\tmp'
New-Item -ItemType Directory -Force $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding $false
$script:fails = 0

function Lua([string]$name, [string]$code) { $p = Join-Path $tmp "$name.lua"; [IO.File]::WriteAllText($p, $code, $enc); $p }
function Send([string]$file, [switch]$ReadOnly, [string]$Label = 'test') {
  $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $send, '-File', $file, '-Label', $Label)
  if ($ReadOnly) { $a += '-ReadOnly' }
  $raw = (& powershell.exe @a) -join "`n"
  $obj = $null; try { $obj = $raw | ConvertFrom-Json } catch { }
  [pscustomobject]@{ raw = $raw; json = $obj; code = $LASTEXITCODE }
}
function Check([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { Write-Output "PASS protocol: $name" } else { Write-Output "FAIL protocol: $name -- $detail"; $script:fails++ }
}

# 1 basic round trip + versions
$r = Send (Lua 'p_ping' 'return { sum = 1 + 1, v = H.version }') -ReadOnly
Check 'round trip' ($r.code -eq 0 -and $r.json.ok -and $r.json.result.sum -eq 2) $r.raw
Check 'versions reported' ($r.json.bridge -and $r.json.helpers -and -not $r.json.helpers_error) $r.raw

# 2 compile error
$r = Send (Lua 'p_compile' 'return (') -ReadOnly
Check 'compile error -> ok:false, exit 4' ($r.code -eq 4 -and -not $r.json.ok -and $r.json.error -like 'compile:*') $r.raw

# 3 runtime error with traceback
$r = Send (Lua 'p_runtime' 'local x = nil; return x.y') -ReadOnly
Check 'runtime error -> ok:false + traceback' (-not $r.json.ok -and $r.json.error -like '*traceback*') $r.raw

# 4 unicode both ways
$r = Send (Lua 'p_unicode' 'return "垃圾車 給愛麗絲 ü ✓"') -ReadOnly
Check 'unicode round trip' ($r.json.result -eq '垃圾車 給愛麗絲 ü ✓') $r.raw

# 5 log() collects strings and tables
$r = Send (Lua 'p_log' 'log("hi", { a = 1 }); print("p"); return true') -ReadOnly
Check 'log() and print()' ($r.json.log.Count -eq 2 -and $r.json.log[0] -eq 'hi {"a":1}' -and $r.json.log[1] -eq 'p') $r.raw

# 6 large result
$r = Send (Lua 'p_big' 'local t = {} for i = 1, 20000 do t[i] = i end return t') -ReadOnly
Check 'large result (20000 items)' ($r.json.ok -and $r.json.result.Count -eq 20000) "code=$($r.code) len=$($r.raw.Length)"

# 7 special values: nan/inf -> null, empty table -> []
$r = Send (Lua 'p_special' 'return { n = 0/0, i = math.huge, e = {}, f = 0.5 }') -ReadOnly
Check 'nan/inf -> null, {} -> []' ($r.raw.Contains('"e":[]') -and $r.raw.Contains('"i":null') -and $r.raw.Contains('"n":null') -and $r.raw.Contains('"f":0.5')) $r.raw

# 8 concurrency: 4 clients at once, each must get its own answer
$jobs = 1..4 | ForEach-Object {
  $f = Lua "p_conc_$_" "local t0 = reaper.time_precise(); while reaper.time_precise() - t0 < 0.3 do end; return 'tag$_'"
  Start-Job -ArgumentList $send, $f -ScriptBlock {
    param($send, $f)
    (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -File $f -ReadOnly) -join ''
  }
}
$outs = $jobs | Wait-Job -Timeout 120 | Receive-Job
$jobs | Remove-Job -Force
$tags = @($outs | ForEach-Object { try { ($_ | ConvertFrom-Json).result } catch { 'bad' } })
Check 'concurrent clients serialized (4/4 own answers)' ((($tags | Sort-Object) -join ',') -eq 'tag1,tag2,tag3,tag4') ($outs -join ' | ')

# 9 stale lock from a dead process is taken over
$lock = Join-Path $env:APPDATA 'REAPER\Scripts\ClaudeBridge\lock'
[IO.File]::WriteAllText($lock, "999999|$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())|crashed agent", $enc)
$r = Send (Lua 'p_stale' 'return "after stale lock"') -ReadOnly
Check 'stale lock recovered' ($r.json.result -eq 'after stale lock' -and -not (Test-Path $lock)) $r.raw

# 10 helpers hot reload (edit helpers.lua, see the change, restore)
$hp = Join-Path $root 'bridge\helpers.lua'
$orig = [IO.File]::ReadAllText($hp, $enc)
try {
  $probe = [regex]::Replace($orig, 'return H\s*$', "H._reload_probe = 'probe-ok'`nreturn H`n")
  if ($probe -eq $orig) { throw 'helpers.lua must end with "return H"' }
  [IO.File]::WriteAllText($hp, $probe, $enc)
  $r = Send (Lua 'p_reload' 'return H._reload_probe') -ReadOnly
  Check 'helpers hot reload' ($r.json.result -eq 'probe-ok') $r.raw
  # broken helpers must not take the bridge down: previous helpers stay active + error reported
  [IO.File]::WriteAllText($hp, $orig + "`nthis is not lua(", $enc)
  $r = Send (Lua 'p_broken' 'return H.n("C4")') -ReadOnly
  Check 'broken helpers keep previous version + report error' ($r.json.ok -and $r.json.result -eq 60 -and $r.json.helpers_error -like '*compile*') $r.raw
} finally {
  [IO.File]::WriteAllText($hp, $orig, $enc)
}
$r = Send (Lua 'p_restored' 'return H._reload_probe == nil') -ReadOnly
Check 'helpers restored' ($r.json.result -eq $true -and -not $r.json.helpers_error) $r.raw

# 11 usage errors from the client itself
$raw = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $send -File (Join-Path $tmp 'does_not_exist.lua')) -join ''
Check 'missing file -> exit 1' ($LASTEXITCODE -eq 1 -and $raw -like '*file not found*') $raw

exit $script:fails
