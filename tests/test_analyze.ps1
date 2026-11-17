# tests/test_analyze.ps1 - analyze.ps1 against a synthetic WAV with known properties (no REAPER needed)
# 2 s, 44.1 kHz, 16-bit stereo, 1 kHz sine, left at 0.5, right at 0.25 (-> L-R = +6.02 dB)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tmp = Join-Path $root 'tests\tmp'; New-Item -ItemType Directory -Force $tmp | Out-Null
$wav = Join-Path $tmp 'sine_1k.wav'
$fails = 0
function Check([string]$name, [bool]$cond, [string]$detail) {
  if ($cond) { Write-Output "PASS analyze: $name" } else { Write-Output "FAIL analyze: $name -- $detail"; $script:fails++ }
}

$rate = 44100; $n = $rate * 2
$ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter $ms
$bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $bw.Write([int](36 + $n * 4)); $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
$bw.Write([int]16); $bw.Write([int16]1); $bw.Write([int16]2); $bw.Write([int]$rate); $bw.Write([int]($rate * 4)); $bw.Write([int16]4); $bw.Write([int16]16)
$bw.Write([Text.Encoding]::ASCII.GetBytes('data')); $bw.Write([int]($n * 4))
for ($i = 0; $i -lt $n; $i++) {
  $s = [Math]::Sin(2 * [Math]::PI * 1000 * $i / $rate)
  $bw.Write([int16]([Math]::Round($s * 0.5 * 32767))); $bw.Write([int16]([Math]::Round($s * 0.25 * 32767)))
}
$bw.Flush(); [IO.File]::WriteAllBytes($wav, $ms.ToArray())

$out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\analyze.ps1') $wav) -join "`n"
Check 'runs' ($LASTEXITCODE -eq 0 -and $out -like '*band energy*') $out
$peak = [regex]::Match($out, 'peak: (-?[\d.]+) dBFS').Groups[1].Value
Check 'peak = -6.0 dBFS' ([Math]::Abs([double]$peak - (-6.02)) -lt 0.15) "peak=$peak"
Check 'loudest band is 1000-2000 Hz' ($out -match '1000-2000\s+Hz\s+0\.0') $out
$top = [regex]::Match($out, 'strongest peaks: (\d+)Hz').Groups[1].Value
Check 'strongest peak ~1000 Hz' ([Math]::Abs([int]$top - 1000) -le 6) "top=$top"
$lr = [regex]::Matches($out, '^\s+0s\s+(-?[\d.]+)\s+(-?[\d.]+)', 'Multiline')
Check 'L-R balance +6.0 dB' ($lr.Count -gt 0 -and [Math]::Abs([double]$lr[0].Groups[2].Value - 6.02) -lt 0.2) "lr=$($lr[0].Groups[2].Value)"
exit $fails
