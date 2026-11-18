# reaper-agent

Claude drives REAPER through a Lua bridge; you can edit anything by hand in between.

## Bridge

How to operate it: see `AGENTS.md` (agent rules), `skills/` (portable skills, built with `tools/build-skills.mjs`), `bridge/API.md` (helpers), `ISSUES.md` (known problems).
Commands sent so far: `cmds/` (numbered; `cmds/cli/` for code sent from stdin; `cmds/mcp/` was the old MCP server, now on the `mcp-backup` branch). cmds 00-15 predate bridge v2,
so they use the old client path, but the helpers they call still exist.

## Song: Für Elise, garbage-truck version (`FurElise_GarbageTruck.rpp`)

- 75 BPM (quarter note), 3/8, 31 bars: Pickup | A (2-9) | A' (10-17) | B (18-23) | A'' (24-31)
- Tracks:
  - **Melody**: right hand, Surge XT, velocity 100
  - **Accomp**: left hand, Surge XT, -5 dB, velocity 88
  - **Loudspeaker**: bus. Both instruments send here only (master send off).

### Sound design
| Stage | Settings | Purpose |
|---|---|---|
| Surge XT osc 1 | Classic, Shape 100% (square), width 50% | melody-chip square wave |
| Surge XT osc 2 | square, +1 octave, -11 dB | shrill, piercing tone |
| Surge XT | Drift 4%; Amp EG A 0 / D 500 ms / S 55% / R 90 ms | cheap chip clock; hard attack, short decay |
| JS: Saturation | 60% | overdriven loudspeaker amp |
| ReaEQ | HP 480 Hz; low shelf 250 Hz -8 dB; 900 Hz +2; 1.7 kHz +7 dB (BW 1.2); high shelf 4.2 kHz -22 dB | horn speaker band-limit + honk |
| ReaDelay | 130 ms, fb -14 dB, 500 Hz - 3 kHz, wet -11 dB | slap-back off buildings |
| ReaVerbate | room 65, damp 70, wet -16 dB | street ambience |
| JS: Master Limiter | threshold -6 dB | loud and flat |

v1 analysis: peak -0.1 dBFS, RMS -14.6 dBFS, energy concentrated 500 Hz-4 kHz (peak band 1-2 kHz).

## v2: depth and atmosphere (`renders/FurElise_GarbageTruck_v2.wav`)

Feedback on v1: not enough layering, not enough atmosphere.

Signal flow:
```
Melody ─┐
Accomp ─┼─> Loudspeaker (saturation, horn EQ, limiter) ─┬─> Distance (air-loss EQ + vol/pan automation) ─> master
Bell ───┘                                                ├─> Street Echo  (-15 dB send: L 170 ms / R 290 ms reflections)
                                                         └─> Street Reverb (-12 dB send: ReaVerbate room 92, 100% wet)
Dusk Pad ──────> master  (+ Street Reverb -4 dB)
City Ambience ─> master  (+ Street Reverb -10 dB)
master: JS Master Limiter -2 dB
```

Truck movement (Distance track; bar: direct level / pan / air-loss high shelf at 2.5 kHz):
1: -22 dB / -60 / -14 dB → 10: -11 / -35 / -7 → 16: -4 / -15 / -2 → 18-23: 0 / 0..+10 / 0 → 26: -6 / +35 / -4 → 31: -16 / +60 / -10 → 34: -30 / +75 / -16

New layers:
- **Bell**: Surge sine with FM (osc 2 = +1 oct +7 st), D 700 ms, S 0. Melody +12 in A' (10-17) and A'' (24-31). Goes through the loudspeaker.
- **Dusk Pad**: saw, 3-voice unison, LP 24 dB at 900 Hz, A 900 ms / R 2.5 s. Chords enter at A' (vel 55), fullest in B (78), then 64. Bypasses the horn.
- **City Ambience**: Surge noise (color -60%), LP 24 dB at 380 Hz, one long note, -24 dB.

v2 analysis: true peak -0.1 dBFS, RMS -16.9 dBFS (re-measured after the analyze.ps1 peak fix).
Timeline: RMS -23 dB (far, wide, side/mid ≈ 0 dB) → -12 dB in B (close, focused, side/mid -10 dB) → -27 dB leaving.
Known: the tail is still ~1.5 dB left-heavy (the reverb tail is not panned with the truck).

Lessons (bridge):
- FX envelopes store *native* values, not normalized → use `H.automate_display`.
- REAPER silently skips a render if the file exists → the render script deletes it first.

## 2026-11-18: Distance track restored
- The project saved at 12:01 had lost the **Distance** track (nothing else changed). Since Loudspeaker only sends to
  Distance, the dry melody/accomp/bell never reached the master; only the echo and reverb returns were audible.
  Cause unknown: it was already gone (project `[modified]`) before any agent command that day, so most likely a manual delete.
- Restored with `cmds/17_restore_distance.lua`: the track chunk copied verbatim from the previous commit
  (ReaEQ + Volume/Pan, 3 envelopes × 8 points, receive from Loudspeaker), inserted back as track 5.
- Check render (not kept): peak -0.1 dBFS, RMS -16.7 dBFS; timeline -23 → -12 (B, side/mid -10) → -26 dB again,
  within ~1 dB of v2, i.e. the truck movement is back. Bands within 0.7 dB of v2.
