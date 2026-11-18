# bridge.ps1 - status / start / stop / restart the REAPER bridge
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\bridge.ps1 status
#   ... start [-Project path.rpp]     (launches REAPER if needed, then the bridge)
#   ... restart                       (after editing bridge\bridge.lua; helpers.lua hot-reloads)
# Prints one JSON object. Exit 0 = bridge running at the end, 2 = not running, 3 = blocked.
param(
  [Parameter(Position = 0)][ValidateSet('status', 'start', 'stop', 'restart')][string]$Action = 'status',
  [string]$Project
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$base = Join-Path $env:APPDATA 'REAPER\Scripts\ClaudeBridge'
$loader = Join-Path $base 'ClaudeBridge.lua'
$hb = Join-Path $base 'heartbeat.txt'
$statusFile = Join-Path $base 'status.json'
$lock = Join-Path $base 'lock'

function Find-Reaper {
  $p = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'REAPER*' } | Select-Object -First 1
  if ($p -and $p.InstallLocation -and (Test-Path (Join-Path $p.InstallLocation 'reaper.exe'))) { return (Join-Path $p.InstallLocation 'reaper.exe') }
  foreach ($c in "$env:ProgramFiles\REAPER (x64)\reaper.exe", "$env:ProgramFiles\REAPER\reaper.exe") { if (Test-Path $c) { return $c } }
  return $null
}
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices; using System.Collections.Generic;
public static class ReaperWindows {
  delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(P p, IntPtr l);
  [DllImport("user32.dll")] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static List<string> Titles(uint target) {
    var r = new List<string>();
    EnumWindows((h, l) => { uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == target && IsWindowVisible(h)) { var s = new StringBuilder(512); GetWindowText(h, s, 512); if (s.Length > 0) r.Add(s.ToString()); }
      return true; }, IntPtr.Zero);
    return r;
  }
}
'@

function Get-State {
  # the main instance = the oldest reaper.exe (a stray "-nonewinst" launcher that became its own
  # instance is newer; see Run-Loader)
  $all = @(Get-Process reaper -ErrorAction SilentlyContinue | Sort-Object StartTime)
  $proc = $all | Select-Object -First 1
  $age = $null
  if (Test-Path $hb) { try { $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]([IO.File]::ReadAllText($hb).Trim()) } catch { } }
  $windows = @(); $dialogs = @()
  if ($proc) {
    $windows = @([ReaperWindows]::Titles([uint32]$proc.Id))
    $dialogs = @($windows | Where-Object { $_ -notmatch ' - REAPER v' -and $_ -notmatch '^(VST|VST3|VSTi|VST3i|JS|CLAP|CLAPi|AU|AUi): ' })
  }
  $bridge = if (-not $proc) { 'reaper-not-running' } elseif ($null -eq $age) { 'stopped' } elseif ($age -le 10) { 'running' } else { 'blocked' }
  $status = $null
  if (Test-Path $statusFile) { try { $status = Get-Content $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
  $lockHolder = $null
  if (Test-Path $lock) { try { $lockHolder = [IO.File]::ReadAllText($lock) } catch { } }
  [ordered]@{
    bridge = $bridge; heartbeat_age_s = $age; reaper_pid = $(if ($proc) { $proc.Id } else { $null })
    installed = (Test-Path $loader); status = $status; dialogs = $dialogs; windows = $windows; lock = $lockHolder
    extra_instances = @($all | Select-Object -Skip 1 | ForEach-Object { $_.Id })
    hint = switch ($bridge) {
      'running' { 'ok' }
      'blocked' { 'bridge is not ticking: REAPER is busy or shows a modal dialog (see dialogs). Ask the user to close it; do not restart.' }
      'stopped' { 'run: node reaper.mjs start' }
      default { 'run: node reaper.mjs start (launches REAPER)' }
    }
  }
}
function Wait-Until([scriptblock]$cond, [int]$sec) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $sec) { if (& $cond) { return $true }; Start-Sleep -Milliseconds 250 }
  return $false
}
# Hand the loader to the running REAPER. "-nonewinst" normally forwards and exits within a second;
# if the main instance doesn't answer in time (e.g. it is busy stopping the script) the launcher
# becomes a SECOND REAPER instance. Detect that, kill only that process, wait, and retry.
function Run-Loader($exe) {
  for ($try = 1; $try -le 3; $try++) {
    $p = Start-Process $exe -ArgumentList '-nonewinst', "`"$loader`"" -PassThru
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited -and $sw.Elapsed.TotalSeconds -lt 6) { Start-Sleep -Milliseconds 200 }
    if ($p.HasExited) { return $true }
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue   # stray instance we just created
    Start-Sleep -Seconds 2
  }
  return $false
}
function Emit($st, [string]$note) {
  if ($note) { $st['note'] = $note }
  Write-Output ($st | ConvertTo-Json -Depth 5 -Compress)
  exit $(switch ($st.bridge) { 'running' { 0 } 'blocked' { 3 } default { 2 } })
}

$st = Get-State
if ($Action -eq 'status') { Emit $st }
if (-not $st.installed) { Emit $st 'bridge not installed: run node reaper.mjs install' }
$exe = Find-Reaper
if (-not $exe) { Emit $st 'REAPER not found' }

if ($Action -in 'stop', 'restart') {
  if ($st.bridge -eq 'running') {
    [void](Run-Loader $exe)   # re-running the script stops it (set_action_options 1)
    [void](Wait-Until { -not (Test-Path $hb) } 15)
    Start-Sleep -Seconds 2    # let REAPER finish tearing the script down before a restart
  } elseif ($st.bridge -eq 'blocked') { Emit $st 'refusing to toggle a blocked bridge (it might start a second instance later)' }
  $st = Get-State
  if ($Action -eq 'stop') { Emit $st 'stopped' }
}

# start
if ($st.bridge -eq 'running') { Emit $st 'already running' }
if ($st.bridge -eq 'blocked') { Emit $st }
if ($st.bridge -eq 'reaper-not-running') {
  if ($Project) { Start-Process $exe -ArgumentList "`"$((Resolve-Path $Project).Path)`"" } else { Start-Process $exe }
  [void](Wait-Until { $p = Get-Process reaper -ErrorAction SilentlyContinue; $p -and $p.MainWindowTitle -like '*REAPER v*' } 90)
  Start-Sleep -Seconds 2
}
if (-not (Run-Loader $exe)) { Emit (Get-State) 'REAPER did not accept the script (launcher kept turning into a new instance)' }
[void](Wait-Until { Test-Path $hb } 30)
$st = Get-State
Emit $st $(if ($st.bridge -eq 'running') { 'started' } else { 'failed to start: check dialogs' })
