//! Cyclic thematic transformation: one theme carried across movements by explicit maps.
//!
//! Two families, after the way Ravel's and Debussy's string quartets bring their opening material
//! back (see `docs/cyclic_transformation_spec.md`; the presets are illustrative, not transcriptions):
//!
//! - **Affine** (Ravel-like): the whole theme moves as a rigid body. Pitch, time and dynamics each
//!   get `x' = a·(x − x0) + b`, i.e. the diagonal matrix
//!   `[P t D]' = diag(c, α, γ)·[P t D] + [T β δ]`. On top of that a piecewise-linear time warp
//!   re-bars it into an asymmetric meter (4/4 bar → 3+2 or 2+3 eighths).
//! - **Cellular** (Debussy-like): only the theme's topology is kept — the order and direction of
//!   its intervals (its contour) — while interval sizes, pitch space, tempo and articulation change
//!   freely: re-realisation in another pitch set, diminution, pointillism, and dilation of a
//!   fragment.
//!
//! Everything works on `melodic_canon::NoteEvent` (MIDI keynum, grid ticks), is total (no panics
//! on any input), deterministic, and keeps events in input order.

use core::array::ArrayTrait;
use koji::composition::melodic_canon::NoteEvent;
use koji::math::Time;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

// ─────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────

fn clamp_keynum(p: i32) -> u8 {
    if p < 0 {
        0
    } else if p > 127 {
        127
    } else {
        p.try_into().unwrap()
    }
}

fn clamp_velocity(v: i32) -> u8 {
    if v < 1 {
        1
    } else if v > 127 {
        127
    } else {
        v.try_into().unwrap()
    }
}

/// `num / den` rounded to nearest, halves away from zero. `den` must be > 0 (callers guard it).
fn div_round(num: i32, den: i32) -> i32 {
    if num >= 0 {
        (2 * num + den) / (2 * den)
    } else {
        -((2 * (-num) + den) / (2 * den))
    }
}

fn sign(x: i32) -> i32 {
    if x > 0 {
        1
    } else if x < 0 {
        -1
    } else {
        0
    }
}

fn pc_of(p: i32) -> u32 {
    let m = p % 12;
    let m = if m < 0 {
        m + 12
    } else {
        m
    };
    m.try_into().unwrap()
}

fn pow2_u16(n: u32) -> u16 {
    let mut r: u16 = 1;
    let mut i = 0;
    while i < n {
        r *= 2;
        i += 1;
    };
    r
}

// ─────────────────────────────────────────────────────────────
// Pitch sets (12-bit masks relative to a tonic pitch class)
// ─────────────────────────────────────────────────────────────

/// Bit k set = pitch class (tonic + k) mod 12 is in the set.
pub const MASK_CHROMATIC: u16 = 0xFFF;
pub const MASK_MAJOR: u16 = 0xAB5; // 0 2 4 5 7 9 11
pub const MASK_NATURAL_MINOR: u16 = 0x5AD; // 0 2 3 5 7 8 10
pub const MASK_WHOLE_TONE: u16 = 0x555; // 0 2 4 6 8 10
pub const MASK_MAJOR_PENTATONIC: u16 = 0x295; // 0 2 4 7 9

pub fn in_pc_set(p: i32, tonic_pc: u8, mask: u16) -> bool {
    let rel = pc_of(p - tonic_pc.into());
    (mask / pow2_u16(rel)) % 2 == 1
}

/// Nearest member of the set to `p`; on a tie, the one in direction `prefer` (+1 up, −1 down,
/// 0 = down). An empty mask leaves `p` alone.
pub fn snap_pitch(p: i32, tonic_pc: u8, mask: u16, prefer: i32) -> i32 {
    if mask % 4096 == 0 || in_pc_set(p, tonic_pc, mask) {
        return p;
    }
    let mut d: i32 = 1;
    loop {
        let up = in_pc_set(p + d, tonic_pc, mask);
        let down = in_pc_set(p - d, tonic_pc, mask);
        if up && down {
            break if prefer > 0 {
                p + d
            } else {
                p - d
            };
        }
        if up {
            break p + d;
        }
        if down {
            break p - d;
        }
        d += 1;
    }
}

/// Next member of the set strictly above (`dir` > 0) or below (`dir` < 0) `p`.
pub fn step_in_pc_set(p: i32, tonic_pc: u8, mask: u16, dir: i32) -> i32 {
    if mask % 4096 == 0 || dir == 0 {
        return p + dir;
    }
    let mut q = p + sign(dir);
    while !in_pc_set(q, tonic_pc, mask) {
        q += sign(dir);
    };
    q
}

pub fn snap_events(events: Span<NoteEvent>, tonic_pc: u8, mask: u16) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        let mut n = *e;
        n.pitch = clamp_keynum(snap_pitch((*e.pitch).into(), tonic_pc, mask, 0));
        out.append(n);
    };
    out
}

/// Like `snap_events`, but a tie resolves toward the previous snapped note (smaller motion, as a
/// contraction intends); the first note's tie goes down.
pub fn snap_events_smooth(events: Span<NoteEvent>, tonic_pc: u8, mask: u16) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    let mut prev: Option<i32> = Option::None;
    for e in events {
        let p: i32 = (*e.pitch).into();
        let prefer = match prev {
            Option::Some(q) => sign(q - p),
            Option::None => 0,
        };
        let mut n = *e;
        n.pitch = clamp_keynum(snap_pitch(p, tonic_pc, mask, prefer));
        prev = Option::Some(n.pitch.into());
        out.append(n);
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Affine family
// ─────────────────────────────────────────────────────────────

/// `x' = num/den · (x − center) + center + offset` on each axis.
/// Pitch: `pitch_num/pitch_den` is the interval factor c (c < 1 contracts the theme's intervals
/// toward `pitch_center`, c < 0 inverts it), `transpose` is T. Time: onsets and durations are
/// scaled by α = `time_num/time_den` and shifted by β = `time_offset`. Dynamics: γ, δ.
#[derive(Copy, Drop, Serde)]
pub struct AffineMap {
    pub pitch_center: u8,
    pub pitch_num: i32,
    pub pitch_den: i32,
    pub transpose: i32,
    pub time_num: u32,
    pub time_den: u32,
    pub time_offset: u32,
    pub vel_num: u32,
    pub vel_den: u32,
    pub vel_offset: i32,
}

pub fn affine_identity(center: u8) -> AffineMap {
    AffineMap {
        pitch_center: center,
        pitch_num: 1,
        pitch_den: 1,
        transpose: 0,
        time_num: 1,
        time_den: 1,
        time_offset: 0,
        vel_num: 1,
        vel_den: 1,
        vel_offset: 0,
    }
}

pub fn affine_pitch(p: u8, m: @AffineMap) -> u8 {
    let den = if *m.pitch_den == 0 {
        1
    } else {
        *m.pitch_den
    };
    let num = if *m.pitch_den == 0 {
        1
    } else {
        *m.pitch_num
    };
    let c: i32 = (*m.pitch_center).into();
    let x: i32 = p.into();
    clamp_keynum(c + div_round(num * (x - c), den) + *m.transpose)
}

fn scale_u32(x: u32, num: u32, den: u32) -> u32 {
    if den == 0 {
        x
    } else {
        let wide: u64 = x.into() * num.into() / den.into();
        if wide > 0xFFFFFFFF {
            0xFFFFFFFF
        } else {
            wide.try_into().unwrap()
        }
    }
}

pub fn affine_map(events: Span<NoteEvent>, m: AffineMap) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        let on = scale_u32(*e.time, m.time_num, m.time_den);
        let off = scale_u32(*e.time + *e.duration, m.time_num, m.time_den);
        let dur = if off > on {
            off - on
        } else {
            1
        };
        let v: i32 = scale_u32((*e.velocity).into(), m.vel_num, m.vel_den).try_into().unwrap();
        out
            .append(
                NoteEvent {
                    time: on + m.time_offset,
                    duration: dur,
                    pitch: affine_pitch(*e.pitch, @m),
                    velocity: clamp_velocity(v + m.vel_offset),
                    voice_id: *e.voice_id,
                },
            );
    };
    out
}

/// Piecewise-linear re-barring (the time integral of a step-function tempo σ). Each source bar of
/// `src_bar` ticks is cut into `groups.len()` equal segments; segment k is stretched or squeezed
/// onto `groups[k]` ticks. With `groups = [3e, 2e]` a 4/4 bar becomes a 5/8 bar of 3+2: beats 1–2
/// fill the long pulse, beats 3–4 the short one. Monotone, so order and overlaps are kept.
pub fn meter_warp_tick(x: u32, src_bar: u32, groups: Span<u32>) -> u32 {
    let n = groups.len();
    if n == 0 || src_bar == 0 {
        return x;
    }
    let mut dst_bar: u64 = 0;
    for g in groups {
        dst_bar += (*g).into();
    };
    let bar: u64 = (x / src_bar).into();
    let within: u64 = (x % src_bar).into();
    let n64: u64 = n.into();
    let sb: u64 = src_bar.into();
    let k: u32 = (within * n64 / sb).try_into().unwrap();
    let mut prefix: u64 = 0;
    let mut i = 0;
    while i < k {
        prefix += (*groups.at(i)).into();
        i += 1;
    };
    let g: u64 = (*groups.at(k)).into();
    let local = (within * n64 - k.into() * sb) * g / sb;
    let r = bar * dst_bar + prefix + local;
    if r > 0xFFFFFFFF {
        0xFFFFFFFF
    } else {
        r.try_into().unwrap()
    }
}

pub fn meter_warp(events: Span<NoteEvent>, src_bar: u32, groups: Span<u32>) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        let on = meter_warp_tick(*e.time, src_bar, groups);
        let off = meter_warp_tick(*e.time + *e.duration, src_bar, groups);
        let mut n = *e;
        n.time = on;
        n.duration = if off > on {
            off - on
        } else {
            1
        };
        out.append(n);
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Cellular family
// ─────────────────────────────────────────────────────────────

/// Successive pitch intervals in semitones (the theme's "seed vector").
pub fn interval_vector(events: Span<NoteEvent>) -> Array<i32> {
    let mut out = ArrayTrait::new();
    let mut i = 1;
    while i < events.len() {
        let a: i32 = (*events.at(i - 1).pitch).into();
        let b: i32 = (*events.at(i).pitch).into();
        out.append(b - a);
        i += 1;
    };
    out
}

/// Direction of each interval: +1, 0, −1. Two themes with equal contours are "the same shape".
pub fn contour(events: Span<NoteEvent>) -> Array<i32> {
    let mut out = ArrayTrait::new();
    for d in interval_vector(events) {
        out.append(sign(d));
    };
    out
}

pub fn same_contour(a: Span<NoteEvent>, b: Span<NoteEvent>) -> bool {
    let ca = contour(a);
    let cb = contour(b);
    if ca.len() != cb.len() {
        return false;
    }
    let mut i = 0;
    let mut ok = true;
    while i < ca.len() {
        if *ca.at(i) != *cb.at(i) {
            ok = false;
            break;
        }
        i += 1;
    };
    ok
}

/// Re-realise the theme inside another pitch set while keeping its contour exactly. Each interval
/// aims for the same size in semitones, lands on the nearest set member, and if that would flatten
/// or reverse the step it moves one set member in the original direction instead. Repeated notes
/// stay repeated. Same rhythm and dynamics. The first note snaps to the set (`start_shift` first).
pub fn homeomorph(
    events: Span<NoteEvent>, tonic_pc: u8, mask: u16, start_shift: i32,
) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    if events.len() == 0 {
        return out;
    }
    let first: i32 = (*events.at(0).pitch).into();
    let mut prev = snap_pitch(first + start_shift, tonic_pc, mask, 0);
    let mut e0 = *events.at(0);
    e0.pitch = clamp_keynum(prev);
    out.append(e0);
    let mut i = 1;
    while i < events.len() {
        let d: i32 = (*events.at(i).pitch).into() - (*events.at(i - 1).pitch).into();
        let s = sign(d);
        let mut q = if s == 0 {
            prev
        } else {
            snap_pitch(prev + d, tonic_pc, mask, s)
        };
        if s != 0 && sign(q - prev) != s {
            q = step_in_pc_set(prev, tonic_pc, mask, s);
        }
        let mut e = *events.at(i);
        e.pitch = clamp_keynum(q);
        out.append(e);
        prev = q;
        i += 1;
    };
    out
}

/// Diminution/augmentation by a rational factor Λ_t, measured from the theme's first onset.
pub fn time_scale(events: Span<NoteEvent>, num: u32, den: u32) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    if events.len() == 0 {
        return out;
    }
    let t0 = *events.at(0).time;
    for e in events {
        let rel = if *e.time >= t0 {
            *e.time - t0
        } else {
            0
        };
        let on = scale_u32(rel, num, den);
        let off = scale_u32(rel + *e.duration, num, den);
        let mut n = *e;
        n.time = t0 + on;
        n.duration = if off > on {
            off - on
        } else {
            1
        };
        out.append(n);
    };
    out
}

/// Pointillism (pizzicato): keep every onset, shorten each sound to `num/den` of its length
/// (at least one tick) and set a flat velocity — a "point cloud" of the line.
pub fn pointillize(events: Span<NoteEvent>, num: u32, den: u32, velocity: u8) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        let mut n = *e;
        let d = scale_u32(*e.duration, num, den);
        n.duration = if d == 0 {
            1
        } else {
            d
        };
        n.velocity = clamp_velocity(velocity.into());
        out.append(n);
    };
    out
}

/// The magnifying glass: take `len` notes from `start` and stretch them by `factor`, so a fragment
/// of the theme spans several slow bars. Rebased to start at the fragment's own first onset.
pub fn dilate_fragment(
    events: Span<NoteEvent>, start: u32, len: u32, factor: u32,
) -> Array<NoteEvent> {
    let mut frag = ArrayTrait::new();
    let mut i = start;
    while i < events.len() && i < start + len {
        frag.append(*events.at(i));
        i += 1;
    };
    time_scale(frag.span(), factor, 1)
}

/// Scale velocities by `num/den` (the dynamic damping of a slow movement, or a crescendo).
pub fn dynamics(events: Span<NoteEvent>, num: u32, den: u32, offset: i32) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        let mut n = *e;
        let v: i32 = scale_u32((*e.velocity).into(), num, den).try_into().unwrap();
        n.velocity = clamp_velocity(v + offset);
        out.append(n);
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Cycles: a theme carried through a set of movements
// ─────────────────────────────────────────────────────────────

/// Ticks per quarter note used by the presets and the demo.
pub const CYCLIC_TPQ: u32 = 4;

/// Ravel-like cycle: [movement 1 = the theme, finale = the affine image re-barred 3+2].
/// Finale: intervals × 2/3 about the first note, down a minor third (F → D), snapped back into
/// D natural minor so contraction stays diatonic (ties toward the previous note), one 4/4 bar
/// (16 ticks) → 5/8 of 3+2 eighths (6 + 4 ticks), velocity × 3/2 + 10.
pub fn ravel_cycle(theme: Span<NoteEvent>) -> Array<Array<NoteEvent>> {
    let mut out = ArrayTrait::new();
    out.append(copy(theme));
    if theme.len() == 0 {
        out.append(ArrayTrait::new());
        return out;
    }
    let center = *theme.at(0).pitch;
    let m = AffineMap {
        pitch_center: center,
        pitch_num: 2,
        pitch_den: 3,
        transpose: -3,
        time_num: 1,
        time_den: 1,
        time_offset: 0,
        vel_num: 3,
        vel_den: 2,
        vel_offset: 10,
    };
    let moved = affine_map(theme, m);
    let tonic_pc: u8 = ((center.into() + 9_u32) % 12).try_into().unwrap(); // a minor third below
    let diatonic = snap_events_smooth(moved.span(), tonic_pc, MASK_NATURAL_MINOR);
    let groups = array![6_u32, 4];
    out.append(meter_warp(diatonic.span(), 4 * CYCLIC_TPQ, groups.span()));
    out
}

/// Debussy-like cycle: [seed, scherzo, slow movement, return].
/// Scherzo: diminution × 2/3 (triplet motion) and pizzicato (⅓ length, flat velocity 72).
/// Slow movement: the first three notes dilated × 4, re-realised in the whole-tone set on the
/// theme's first note (contour kept), velocity halved. Return: the seed, unchanged.
pub fn debussy_cycle(theme: Span<NoteEvent>) -> Array<Array<NoteEvent>> {
    let mut out = ArrayTrait::new();
    out.append(copy(theme));
    let scherzo = time_scale(theme, 2, 3);
    out.append(pointillize(scherzo.span(), 1, 3, 72));
    let tonic_pc: u8 = if theme.len() == 0 {
        0
    } else {
        (*theme.at(0).pitch % 12)
    };
    let frag = dilate_fragment(theme, 0, 3, 4);
    let whole = homeomorph(frag.span(), tonic_pc, MASK_WHOLE_TONE, 0);
    out.append(dynamics(whole.span(), 1, 2, 0));
    out.append(copy(theme));
    out
}

fn copy(events: Span<NoteEvent>) -> Array<NoteEvent> {
    let mut out = ArrayTrait::new();
    for e in events {
        out.append(*e);
    };
    out
}

// ─────────────────────────────────────────────────────────────
// Laws (cheap self-checks, also asserted in tests)
// ─────────────────────────────────────────────────────────────

/// Identity map changes nothing; c = 1 maps compose by adding transpositions; contraction
/// with c ≥ 0 keeps the contour except where an interval rounds to zero; the warp is monotone.
pub fn cyclic_laws_hold(theme: Span<NoteEvent>) -> bool {
    if theme.len() == 0 {
        return true;
    }
    let c = *theme.at(0).pitch;
    let id = affine_map(theme, affine_identity(c));
    let mut ok = events_equal(theme, id.span());

    let mut up2 = affine_identity(c);
    up2.transpose = 2;
    let mut up5 = affine_identity(c);
    up5.transpose = 5;
    let mut up7 = affine_identity(c);
    up7.transpose = 7;
    let twice = affine_map(affine_map(theme, up2).span(), up5);
    ok = ok && events_equal(twice.span(), affine_map(theme, up7).span());

    let groups = array![6_u32, 4];
    let mut last: u32 = 0;
    let mut x: u32 = 0;
    while x < 64 {
        let y = meter_warp_tick(x, 16, groups.span());
        if x > 0 && y < last {
            ok = false;
        }
        last = y;
        x += 1;
    };
    ok
}

pub fn events_equal(a: Span<NoteEvent>, b: Span<NoteEvent>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    let mut ok = true;
    while i < a.len() {
        let x = *a.at(i);
        let y = *b.at(i);
        if x.time != y.time
            || x.duration != y.duration
            || x.pitch != y.pitch
            || x.velocity != y.velocity
            || x.voice_id != y.voice_id {
            ok = false;
            break;
        }
        i += 1;
    };
    ok
}

// ─────────────────────────────────────────────────────────────
// Demo theme and MIDI rendering
// ─────────────────────────────────────────────────────────────

/// An original 7-note, two-bar theme in F major (not a quotation), 4/4, `CYCLIC_TPQ` ticks per quarter.
pub fn demo_theme() -> Array<NoteEvent> {
    let pitches = array![65_u8, 69, 72, 70, 69, 67, 65];
    let durs = array![4_u32, 4, 6, 2, 4, 4, 8];
    let mut out = ArrayTrait::new();
    let mut t: u32 = 0;
    let mut i = 0;
    while i < 7 {
        out
            .append(
                NoteEvent {
                    time: t,
                    duration: *durs.at(i),
                    pitch: *pitches.at(i),
                    velocity: 64,
                    voice_id: 0,
                },
            );
        t += *durs.at(i);
        i += 1;
    };
    out
}

/// Movements laid end to end with a gap of `gap` grid ticks, one MIDI channel per movement.
/// `midi_ticks` = MIDI ticks per grid tick: `output_midi_object` writes event times as 480-PPQN
/// ticks, so with `CYCLIC_TPQ` = 4 a sixteenth is 120.
pub fn cycle_to_midi(movements: Span<Array<NoteEvent>>, gap: u32, midi_ticks: u64) -> Midi {
    let mut msgs: Array<Message> = ArrayTrait::new();
    msgs.append(Message::SET_TEMPO(SetTempo { tempo: 500000, time: Option::Some(0) }));
    let mut offset: u32 = 0;
    let mut mv: u32 = 0;
    for movement in movements {
        let ch: u8 = (mv % 16).try_into().unwrap();
        let mut end: u32 = offset;
        for e in movement.span() {
            let on = offset + *e.time;
            let off = on + *e.duration;
            if off > end {
                end = off;
            }
            let on_t: Time = on.into() * midi_ticks;
            let off_t: Time = off.into() * midi_ticks;
            msgs
                .append(
                    Message::NOTE_ON(
                        NoteOn { channel: ch, note: *e.pitch, velocity: *e.velocity, time: on_t },
                    ),
                );
            msgs
                .append(
                    Message::NOTE_OFF(NoteOff { channel: ch, note: *e.pitch, velocity: 64, time: off_t }),
                );
        };
        offset = end + gap;
        mv += 1;
    };
    Midi { events: msgs.span() }
}
