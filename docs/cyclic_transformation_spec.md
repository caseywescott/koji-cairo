# Cyclic thematic transformation

`src/composition/cyclic_transform.cairo` carries one theme across several movements with explicit,
composable maps. It models two ways cyclic form brings material back, after the string quartets of
Ravel (F major, 1903) and Debussy (G minor, 1893). The presets are illustrative parameter choices on
an original demo theme, not transcriptions or analyses of either score.

All functions take and return `melodic_canon::NoteEvent` (MIDI keynum, grid ticks), keep input
order, never panic, and are deterministic.

## Affine family (Ravel-like)

The theme moves as a rigid body. Each axis gets `x' = a·(x − x0) + b`:

```
[P]'   [c  0  0] [P − P0]   [P0 + T]
[t]  = [0  α  0] [t     ] + [β     ]
[D]    [0  0  γ] [D     ]   [δ     ]
```

| Symbol | Field | Meaning |
| --- | --- | --- |
| c | `pitch_num / pitch_den` | interval factor about `pitch_center` (c < 1 contracts, c < 0 inverts) |
| T | `transpose` | new tonal centre, in semitones |
| α, β | `time_num / time_den`, `time_offset` | augmentation/diminution and displacement |
| γ, δ | `vel_num / vel_den`, `vel_offset` | dynamic scaling and lift |

Pitch rounds to the nearest semitone (halves away from zero) and clamps to 0–127. A contracted
theme can be snapped back into a scale with `snap_events` (12-bit pitch-class masks:
`MASK_MAJOR`, `MASK_NATURAL_MINOR`, `MASK_WHOLE_TONE`, …).

**Meter warp.** `meter_warp(events, src_bar, groups)` is the time integral of a step-function
tempo: each source bar is cut into `groups.len()` equal segments and segment k is mapped linearly
onto `groups[k]` ticks. With 4 ticks per quarter, `meter_warp(theme, 16, [6, 4])` turns a 4/4 bar
into a 5/8 bar grouped 3+2 (beats 1–2 fill the long pulse, beats 3–4 the short one); `[4, 6]` gives
2+3. The warp is monotone, so order and overlaps survive.

`ravel_cycle(theme)` returns `[theme, finale]`; the finale contracts intervals × 2/3 about the
first note, moves down a minor third, snaps into that natural minor, re-bars 4/4 → 3+2 and plays
louder (× 3/2 + 10).

## Cellular family (Debussy-like)

Only the theme's topology is kept: its interval vector's order and directions (`contour`). Interval
sizes, pitch space, time scale and articulation change freely.

| Function | Operation |
| --- | --- |
| `interval_vector`, `contour`, `same_contour` | the seed vector and its sign pattern |
| `homeomorph(events, tonic_pc, mask, shift)` | re-realise in another pitch set; contour kept exactly |
| `time_scale(events, num, den)` | Λ_t: diminution or augmentation from the first onset |
| `pointillize(events, num, den, vel)` | pizzicato: same onsets, short sounds, flat dynamic |
| `dilate_fragment(events, start, len, factor)` | the magnifying glass on a fragment |
| `dynamics(events, num, den, offset)` | damping or swelling |

`homeomorph` aims each interval at the same size in semitones, lands on the nearest set member, and
if that would flatten or reverse the step, moves one set member in the original direction instead,
so semitone motion in a whole-tone set becomes whole-tone motion with the same shape.

`debussy_cycle(theme)` returns `[seed, scherzo, slow, return]`: the scherzo is × 2/3 (triplet
motion) and pizzicato; the slow movement dilates the first three notes × 4, re-realises them in the
whole-tone set on the first note's pitch class, and halves the dynamic.

## Laws

`cyclic_laws_hold(theme)` checks: the identity map changes nothing; c = 1 maps compose by adding
transpositions; the meter warp is monotone. Tests also check that `homeomorph`, `time_scale` and
`pointillize` preserve contour, and that every function is total on empty input.

## Listening

```bash
./scripts/generate_cyclic_demo_midis.sh   # writes demos/cyclic/cyclic_demo.mid
```

Channels 0–1: the theme and its Ravel-like finale. Channels 2–5: the Debussy-like seed, scherzo,
slow movement and return. 120 BPM, a sixteenth per tick.
