# tests/run-tests.ps1 - run every test suite; summary in tests\last-run.log; exit 1 on any failure.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1 [-Only protocol,helpers,analyze,cli,skills]
# Needs REAPER + bridge running (tools\bridge.ps1 start). Never touches the open song:
# helper tests run in a temporary project tab (see test_helpers.lua).
param([string[]]$Only = @('analyze', 'protocol', 'helpers', 'cli', 'skills'))
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tests = Join-Path $root 'tests'
$tmp = Join-Path $tests 'tmp'
New-Item -ItemType Directory -Force $tmp | Out-Null
$enc = New-Object System.Text.UTF8Encoding $false
$lines = New-Object System.Collections.Generic.List[string]
function Invoke-Pwsh([string[]]$a) { (& powershell.exe -NoProfile -ExecutionPolicy Bypass @a) }

$st = (Invoke-Pwsh @('-File', (Join-Path $root 'tools\bridge.ps1'), 'status')) -join '' | ConvertFrom-Json
$needBridge = @($Only | Where-Object { $_ -notin @('analyze', 'skills') }).Count -gt 0
if ($needBridge -and $st.bridge -ne 'running') {
  $lines.Add("FAIL setup: bridge is '$($st.bridge)' ($($st.hint)) dialogs: $($st.dialogs -join '; ')")
  $Only = @($Only | Where-Object { $_ -in @('analyze', 'skills') })
}

if ($Only -contains 'analyze') { (Invoke-Pwsh @('-File', (Join-Path $tests 'test_analyze.ps1'))) | ForEach-Object { $lines.Add($_) } }
if ($Only -contains 'protocol') { (Invoke-Pwsh @('-File', (Join-Path $tests 'test_protocol.ps1'))) | ForEach-Object { $lines.Add($_) } }
if ($Only -contains 'helpers') {
  Copy-Item (Join-Path $tests 'fixtures\empty.rpp') (Join-Path $tmp 'run.rpp') -Force
  $code = [IO.File]::ReadAllText((Join-Path $tests 'test_helpers.lua'), $enc).Replace('__TMP_DIR__', $tmp)
  $f = Join-Path $tmp 'test_helpers.run.lua'; [IO.File]::WriteAllText($f, $code, $enc)
  $raw = (Invoke-Pwsh @('-File', (Join-Path $root 'tools\send.ps1'), '-File', $f, '-ReadOnly', '-Label', 'tests', '-TimeoutSec', '300')) -join "`n"
  $j = $null; try { $j = $raw | ConvertFrom-Json } catch { }
  if (-not $j -or -not $j.ok) { $lines.Add("FAIL helpers: suite crashed -- $raw") }
  else {
    foreach ($t in $j.result.results) { if ($t.ok) { $lines.Add("PASS helpers: $($t.name)") } else { $lines.Add("FAIL helpers: $($t.name) -- $($t.err)") } }
    if (-not $j.result.back_on_user_project) { $lines.Add('FAIL helpers: user project was not re-selected after the sandbox tab') }
    else { $lines.Add('PASS helpers: user project re-selected after sandbox') }
  }
}
if ($Only -contains 'cli') { (& node (Join-Path $tests 'test_cli.mjs')) | ForEach-Object { $lines.Add($_) } }
if ($Only -contains 'skills') { (& node (Join-Path $tests 'test_skills.mjs')) | ForEach-Object { $lines.Add($_) } }

$pass = @($lines | Where-Object { $_ -like 'PASS*' }).Count
$fail = @($lines | Where-Object { $_ -like 'FAIL*' }).Count
$summary = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  passed $pass, failed $fail  (suites: $($Only -join ','))"
$log = @($summary) + $lines
[IO.File]::WriteAllLines((Join-Path $tests 'last-run.log'), $log, $enc)
$lines | ForEach-Object { Write-Output $_ }
Write-Output $summary
exit $(if ($fail -gt 0) { 1 } else { 0 })
