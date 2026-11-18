# Bridge API (helpers.lua, `H`)

Every request is Lua run inside REAPER with: `reaper` (full ReaScript API, alias `r`), `H` (below),
`log(...)` / `print(...)` (collected into the reply). `return` a value to get it back as JSON
(MediaTrack/MediaItem pointers come back as strings; return names/indices instead).

Conventions
- **Bars** are 1-based and may be fractional (`2.5` = halfway through bar 2), in the current tempo map.
- **Note positions** inside a MIDI item are quarter notes (QN) from the item start; lengths in QN.
  In 3/8 a bar is 1.5 QN, a sixteenth 0.25 QN.
- **track** = exact track name, 1-based index, or a MediaTrack. **fx** = 0-based index or name substring.
  **param** = 0-based index, exact name, or name substring (first match).
- Each non-readonly request = one undo point `Claude: <label>`. Errors leave partial changes inside that
  undo point, so the user (or you) can undo them.

## Time / tempo
| call | |
|---|---|
| `H.set_tempo(bpm, num?, den?)` | first tempo marker (creates one when a time signature is given) |
| `H.bar_qn(bar)`, `H.bar_time(bar)`, `H.time_bar(seconds)` | conversions |

## Notes / chords
| call | |
|---|---|
| `H.n("Eb4")` → 63 | note names, C4 = 60, `#`/`b`, numbers pass through |
| `H.chord("Fm7", 3)` → `{53,56,60,63}` | qualities: `"" maj m min 5 7 maj7 m7 mmaj7 dim dim7 m7b5 aug sus2 sus4 7sus4 add9 madd9 6 m6 9 maj9 m9 11 m11 13` |

## Tracks / routing
| call | |
|---|---|
| `H.track(ref)` | MediaTrack or nil |
| `H.add_track(name, o)` / `H.get_or_add_track(name, o)` | o: `index, vol_db, pan(-1..1), mute, solo, master_send, color("#RRGGBB"), name` |
| `H.mix(track, o)` | same options as above |
| `H.delete_track(track)` | |
| `H.send(src, dst, db)` | always adds a send |
| `H.ensure_send(src, dst, db)` | idempotent: adds or updates the level |
| `H.sends(track)` | `{ {dest, vol_db}, ... }` |

## Items / MIDI
| call | |
|---|---|
| `H.midi_item(track, start_bar, bars, {name})` → `take, item` | |
| `H.add_notes(take, notes, {vel, ch})` | notes: `{pitch, start_qn, len_qn, vel, ch}` or `{p=,s=,l=,v=,ch=,mute=}`; pitch number or name; velocity clamped 1-127 |
| `H.get_notes(take)` | `{ {p,s,l,v,ch}, ... }` (QN from item start) |
| `H.clear_notes(take)` | |
| `H.items(track)` | `{ {index, take, name, start_bar, end_bar, midi}, ... }` |
| `H.take(track, i)` | take of the i-th item (default 1) |
| `H.delete_items(track, from_bar?, to_bar?)` | items whose start is in [from, to); no bounds = all |

## FX / parameters
| call | |
|---|---|
| `H.installed_fx(filter?)` | names of installed plugins, e.g. `H.installed_fx("Surge")` |
| `H.fx(track, name, {new})` → index | adds if not on the track (`new=true`: always add) |
| `H.fx_list(track)`, `H.clear_fx(track)` | |
| `H.params(track, fx, filter?)` | `{ {i, name, v(normalized), fmt(display)}, ... }` |
| **`H.set(track, fx, param, value)`** | number → by **display value** (`800` Hz, `-6` dB, `1500` ms; `-200` reaches `-inf`); string → by **choice label** (`"LP 24 dB"`, `"On"`). Returns the display string, so check it. |
| `H.param_choices(track, fx, param)` | labels of an enum param |
| `H.set_param(track, fx, param, normalized)` | raw 0..1 |
| `H.parse_display(str)` | `"1.50 s"`→1500, `"1.2 kHz"`→1200, `"-inf"`→-1e12 |

Display search assumes the display is monotonic in the normalized value. Times compare in ms.

## Automation
| call | |
|---|---|
| **`H.automate_display(track, fx, param, points, {clear, shape})`** | points `{ {bar, display_value, shape?}, ... }`; returns the evaluated envelope values to verify. `clear` defaults to true. |
| `H.automate_native(track, fx, param, points, o)` | points in the envelope's native units |
| `H.envelope_values(track, fx, param, bars)` | evaluate an FX envelope |
| ~~`H.automate`~~ | deprecated: normalized values are wrong for non-linear params |

Shapes: 0 linear, 1 square, 2 slow start/end, 3 fast start, 4 fast end, 5 bezier.
Track volume/pan envelopes aren't wrapped: put `JS: Volume/Pan Adjustment (Cockos)` on the track and automate it.

## Markers / transport / project
| call | |
|---|---|
| `H.region(name, start_bar, end_bar, color?)`, `H.marker(name, bar, color?)`, `H.clear_markers()` | |
| `H.cursor(bar)`, `H.play(bar?)`, `H.stop()` | |
| `H.dump({notes, sends})` | snapshot: tempo, timesig, tracks (vol, pan, mute, solo, master_send, fx, items), regions, markers |
| `H.project_file()`, `H.project_dir()` | |
| `H.save()` | saves to the project's own file; errors on a never-saved project (a Save As dialog would block the bridge) |
| `H.render(name, {start_bar, end_bar, tail, dir})` | master → `<project>/renders/<name>.wav`, 24-bit 44.1 kHz; replaces an existing file; restores the project's own render settings afterwards and re-saves a project that was clean before (so it stays clean; unsaved changes are never saved for you); returns `{path, size, seconds, replaced, saved_project}` |

## Things that block the bridge (avoid)
Anything that opens a modal dialog: Save As on an unsaved project, quitting/closing a dirty project,
some render settings, plugin error popups. While a dialog is open the bridge doesn't tick:
`node reaper.mjs status` lists the dialog titles. Ask the user to close them.
