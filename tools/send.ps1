# send.ps1 - run a Lua request inside REAPER through the bridge and print the JSON reply.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\send.ps1 -File cmds\20_x.lua -Label "add drums"
#   ... -File q.lua -ReadOnly          (queries: no undo point)
# Always pass code as a FILE: PowerShell strips double quotes from inline native-command arguments.
# Safe for several agents at once: requests are serialized with a lock file; a lock left by a
# dead process (or older than -LockStaleSec) is taken over.
# Exit codes: 0 ok, 1 usage, 2 bridge not running/blocked, 3 timeout, 4 request error, 5 lock busy
param(
  [string]$File,
  [string]$Label,
  [switch]$ReadOnly,
  [int]$TimeoutSec = 120,
  [int]$LockTimeoutSec = 300,
  [int]$LockStaleSec = 900
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$enc = New-Object System.Text.UTF8Encoding $false
$base = Join-Path $env:APPDATA 'REAPER\Scripts\ClaudeBridge'
$req = Join-Path $base 'inbox\request.lua'
$resp = Join-Path $base 'outbox\response.json'
$hb = Join-Path $base 'heartbeat.txt'
$lock = Join-Path $base 'lock'

function Fail([string]$msg, [int]$code) {
  Write-Output ('{"ok":false,"error":' + (ConvertTo-Json $msg -Compress) + '}')
  exit $code
}
function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function HeartbeatAge {
  if (-not (Test-Path $hb)) { return 99999 }
  try { return (Now) - [int64]([IO.File]::ReadAllText($hb).Trim()) } catch { return 99999 }
}

if (-not $File) { Fail 'usage: send.ps1 -File <code.lua> [-Label text] [-ReadOnly]' 1 }
if (-not (Test-Path $File)) { Fail "file not found: $File" 1 }
$code = [IO.File]::ReadAllText((Resolve-Path $File).Path, $enc)
if (-not (Test-Path (Split-Path $req))) { Fail 'bridge not installed: run tools\install.ps1' 2 }
if (-not (Test-Path $hb)) { Fail 'bridge not running: run tools\bridge.ps1 start' 2 }
$Label = ($Label -replace '[\r\n]', ' ')

# ---- acquire lock
$me = "$PID|$(Now)|$Label"
$sw = [Diagnostics.Stopwatch]::StartNew()
$got = $false
while ($sw.Elapsed.TotalSeconds -lt $LockTimeoutSec) {
  try {
    $fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $b = $enc.GetBytes($me); $fs.Write($b, 0, $b.Length); $fs.Close()
    $got = $true; break
  } catch [System.IO.IOException] {
    $info = $null
    try { $info = [IO.File]::ReadAllText($lock).Split('|') } catch { }
    if ($info -and $info.Count -ge 2) {
      $opid = 0; $ots = 0
      [void][int]::TryParse($info[0], [ref]$opid); [void][int64]::TryParse($info[1], [ref]$ots)
      $alive = $opid -gt 0 -and [bool](Get-Process -Id $opid -ErrorAction SilentlyContinue)
      if (-not $alive -or ((Now) - $ots) -gt $LockStaleSec) {
        Remove-Item $lock -Force -ErrorAction SilentlyContinue; continue
      }
    }
    Start-Sleep -Milliseconds 100
  }
}
if (-not $got) {
  $holder = ''; try { $holder = [IO.File]::ReadAllText($lock) } catch { }
  Fail "bridge busy: lock held by '$holder' for over $LockTimeoutSec s" 5
}

$out = $null; $rc = 0
try {
  # the previous request may have been long (render): wait for a fresh heartbeat
  $w = [Diagnostics.Stopwatch]::StartNew()
  while ((HeartbeatAge) -gt 10 -and $w.Elapsed.TotalSeconds -lt 15) { Start-Sleep -Milliseconds 200 }
  if ((HeartbeatAge) -gt 10) {
    $out = '{"ok":false,"error":"bridge not responding (stale heartbeat). REAPER may show a modal dialog: run tools\\bridge.ps1 status"}'
    $rc = 2
  } else {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $header = "-- id: $id`n"
    if ($Label) { $header += "-- label: $Label`n" }
    if ($ReadOnly) { $header += "-- readonly`n" }
    Remove-Item $req, $resp -Force -ErrorAction SilentlyContinue   # leftovers from a crashed client
    $tmp = "$req.$PID.tmp"
    [IO.File]::WriteAllText($tmp, $header + $code, $enc)
    Move-Item $tmp $req -Force
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
      if (Test-Path $resp) {
        $txt = $null
        try { $txt = [IO.File]::ReadAllText($resp, $enc) } catch { }
        if ($txt -and $txt.Contains("`"id`":`"$id`"")) {
          Remove-Item $resp -Force -ErrorAction SilentlyContinue
          $out = $txt
          $rc = if ($txt.Contains('"ok":true')) { 0 } else { 4 }
          break
        }
      }
      Start-Sleep -Milliseconds 30
    }
    if ($null -eq $out) {
      $out = '{"ok":false,"error":"timeout waiting for REAPER (long operation or a modal dialog: run tools\\bridge.ps1 status)"}'
      $rc = 3
    }
  }
} finally {
  Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
Write-Output $out
exit $rc
