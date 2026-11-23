use koji::composition::cyclic_transform::{
    AffineMap, MASK_MAJOR, MASK_WHOLE_TONE, affine_identity, affine_map, affine_pitch, contour,
    cycle_to_midi, cyclic_laws_hold, debussy_cycle, demo_theme, dilate_fragment, events_equal,
    homeomorph, in_pc_set, interval_vector, meter_warp, meter_warp_tick, pointillize, ravel_cycle,
    same_contour, snap_pitch, time_scale,
};
use koji::composition::melodic_canon::NoteEvent;
use koji::midi::output::output_midi_object;

fn pitches(events: Span<NoteEvent>) -> Array<u8> {
    let mut out = array![];
    for e in events {
        out.append(*e.pitch);
    };
    out
}

fn onsets(events: Span<NoteEvent>) -> Array<u32> {
    let mut out = array![];
    for e in events {
        out.append(*e.time);
    };
    out
}

#[test]
fn demo_theme_shape() {
    let t = demo_theme();
    assert_eq!(t.len(), 7);
    assert_eq!(interval_vector(t.span()), array![4, 3, -2, -1, -2, -2]);
    assert_eq!(contour(t.span()), array![1, 1, -1, -1, -1, -1]);
    assert_eq!(onsets(t.span()), array![0, 4, 8, 14, 16, 20, 24]);
}

#[test]
fn laws_hold_on_demo_theme() {
    let t = demo_theme();
    assert!(cyclic_laws_hold(t.span()));
}

#[test]
fn affine_contraction_rounds_about_center() {
    let m = AffineMap {
        pitch_center: 60,
        pitch_num: 1,
        pitch_den: 2,
        transpose: 0,
        time_num: 1,
        time_den: 1,
        time_offset: 0,
        vel_num: 1,
        vel_den: 1,
        vel_offset: 0,
    };
    assert_eq!(affine_pitch(72, @m), 66);
    assert_eq!(affine_pitch(48, @m), 54);
    assert_eq!(affine_pitch(63, @m), 62); // 1.5 rounds away from zero
    assert_eq!(affine_pitch(57, @m), 58); // −1.5 → −2
    let mut inv = m;
    inv.pitch_num = -1;
    inv.pitch_den = 1;
    assert_eq!(affine_pitch(64, @inv), 56);
}

#[test]
fn affine_time_and_dynamics() {
    let t = demo_theme();
    let mut m = affine_identity(65);
    m.time_num = 1;
    m.time_den = 2;
    m.time_offset = 100;
    m.vel_num = 3;
    m.vel_den = 2;
    m.vel_offset = 10;
    let r = affine_map(t.span(), m);
    assert_eq!(onsets(r.span()), array![100, 102, 104, 107, 108, 110, 112]);
    assert_eq!(*r.at(0).velocity, 106);
    assert_eq!(*r.at(2).duration, 3);
}

#[test]
fn affine_clamps_to_midi_range() {
    let t = demo_theme();
    let mut m = affine_identity(65);
    m.transpose = 100;
    let r = affine_map(t.span(), m);
    assert_eq!(*r.at(0).pitch, 127);
    m.transpose = -100;
    let r = affine_map(t.span(), m);
    assert_eq!(*r.at(0).pitch, 0);
}

#[test]
fn meter_warp_four_four_to_three_two() {
    let g = array![6_u32, 4];
    // beats of a 16-tick 4/4 bar → 0, 3, 6, 8 in a 10-tick 5/8 bar
    assert_eq!(meter_warp_tick(0, 16, g.span()), 0);
    assert_eq!(meter_warp_tick(4, 16, g.span()), 3);
    assert_eq!(meter_warp_tick(8, 16, g.span()), 6);
    assert_eq!(meter_warp_tick(12, 16, g.span()), 8);
    assert_eq!(meter_warp_tick(16, 16, g.span()), 10);
    assert_eq!(meter_warp_tick(24, 16, g.span()), 16);
    let t = demo_theme();
    let w = meter_warp(t.span(), 16, g.span());
    assert_eq!(onsets(w.span()), array![0, 3, 6, 9, 10, 13, 16]);
    assert_eq!(*w.at(6).duration, 4);
}

#[test]
fn meter_warp_two_three() {
    let g = array![4_u32, 6];
    assert_eq!(meter_warp_tick(4, 16, g.span()), 2);
    assert_eq!(meter_warp_tick(8, 16, g.span()), 4);
    assert_eq!(meter_warp_tick(12, 16, g.span()), 7);
}

#[test]
fn meter_warp_empty_groups_is_identity() {
    let t = demo_theme();
    let w = meter_warp(t.span(), 16, array![].span());
    assert!(events_equal(t.span(), w.span()));
}

#[test]
fn pitch_sets() {
    assert!(in_pc_set(62, 0, MASK_MAJOR));
    assert!(!in_pc_set(61, 0, MASK_MAJOR));
    assert!(in_pc_set(66, 0, MASK_WHOLE_TONE));
    assert!(!in_pc_set(65, 0, MASK_WHOLE_TONE));
    assert_eq!(snap_pitch(61, 0, MASK_MAJOR, 1), 62);
    assert_eq!(snap_pitch(61, 0, MASK_MAJOR, -1), 60);
    assert_eq!(snap_pitch(61, 0, 0, 1), 61);
}

#[test]
fn homeomorph_keeps_contour_in_whole_tone() {
    let t = demo_theme();
    let h = homeomorph(t.span(), 5, MASK_WHOLE_TONE, 0);
    assert!(same_contour(t.span(), h.span()));
    assert_eq!(pitches(h.span()), array![65, 69, 73, 71, 69, 67, 65]);
    for e in h.span() {
        assert!(in_pc_set((*e.pitch).into(), 5, MASK_WHOLE_TONE));
    };
}

#[test]
fn homeomorph_never_flattens_a_step() {
    // semitone steps in a whole-tone set would round to repeats; contour must survive
    let mut t = array![];
    let ps = array![60_u8, 61, 62, 61, 60];
    let mut i = 0;
    while i < 5 {
        t.append(NoteEvent { time: i * 2, duration: 2, pitch: *ps.at(i), velocity: 64, voice_id: 0 });
        i += 1;
    };
    let h = homeomorph(t.span(), 0, MASK_WHOLE_TONE, 0);
    assert!(same_contour(t.span(), h.span()));
    assert_eq!(pitches(h.span()), array![60, 62, 64, 62, 60]);
}

#[test]
fn time_scale_and_fragment() {
    let t = demo_theme();
    let d = time_scale(t.span(), 2, 3);
    assert_eq!(onsets(d.span()), array![0, 2, 5, 9, 10, 13, 16]);
    let f = dilate_fragment(t.span(), 1, 3, 4);
    assert_eq!(f.len(), 3);
    assert_eq!(onsets(f.span()), array![4, 20, 44]);
    assert_eq!(*f.at(1).duration, 24);
    let p = pointillize(t.span(), 1, 4, 72);
    assert_eq!(*p.at(6).duration, 2);
    assert_eq!(*p.at(3).duration, 1); // never zero
    assert_eq!(*p.at(0).velocity, 72);
}

#[test]
fn ravel_cycle_finale() {
    let t = demo_theme();
    let c = ravel_cycle(t.span());
    assert_eq!(c.len(), 2);
    assert!(events_equal(c.at(0).span(), t.span()));
    let fin = c.at(1).span();
    // contracted ×2/3 about F4, down a minor third, snapped into D natural minor
    assert_eq!(pitches(fin), array![62, 65, 67, 65, 65, 62, 62]); // Eb ties D/E, ties go down
    assert_eq!(onsets(fin), array![0, 3, 6, 9, 10, 13, 16]);
    assert_eq!(*fin.at(0).velocity, 106);
}

#[test]
fn debussy_cycle_movements() {
    let t = demo_theme();
    let c = debussy_cycle(t.span());
    assert_eq!(c.len(), 4);
    assert!(events_equal(c.at(0).span(), t.span()));
    assert!(events_equal(c.at(3).span(), t.span()));
    let scherzo = c.at(1).span();
    assert!(same_contour(scherzo, t.span()));
    assert_eq!(onsets(scherzo), array![0, 2, 5, 9, 10, 13, 16]);
    let slow = c.at(2).span();
    assert_eq!(slow.len(), 3);
    assert_eq!(pitches(slow), array![65, 69, 73]);
    assert_eq!(onsets(slow), array![0, 16, 32]);
    assert_eq!(*slow.at(0).velocity, 32);
}

#[test]
fn empty_inputs_are_total() {
    let e: Array<NoteEvent> = array![];
    assert_eq!(ravel_cycle(e.span()).len(), 2);
    assert_eq!(debussy_cycle(e.span()).len(), 4);
    assert_eq!(homeomorph(e.span(), 0, MASK_MAJOR, 0).len(), 0);
    assert_eq!(dilate_fragment(e.span(), 3, 3, 4).len(), 0);
    assert!(cyclic_laws_hold(e.span()));
}

/// Prints the demo as hex (one line, prefixed CYCLIC_MIDI_HEX=). Export:
/// `./scripts/generate_cyclic_demo_midis.sh`
#[test]
#[ignore]
fn cyclic_demo_midi_hex() {
    let t = demo_theme();
    let mut movements = ravel_cycle(t.span());
    let mut deb = debussy_cycle(t.span());
    // Ravel pair (ch 0–1), then Debussy's four movements (ch 2–5)
    let mut all = array![];
    while let Option::Some(m) = movements.pop_front() {
        all.append(m);
    };
    while let Option::Some(m) = deb.pop_front() {
        all.append(m);
    };
    let midi = cycle_to_midi(all.span(), 8, 120);
    let bytes = output_midi_object(@midi);
    let hex: ByteArray = "0123456789abcdef";
    let mut s: ByteArray = "";
    for b in bytes {
        s.append_byte(hex.at((b / 16).into()).unwrap());
        s.append_byte(hex.at((b % 16).into()).unwrap());
    };
    println!("CYCLIC_MIDI_HEX={}", s);
}
