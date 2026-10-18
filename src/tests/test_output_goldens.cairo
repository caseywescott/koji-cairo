//! Golden outputs: Poseidon hashes of real Beast scores (engine v1 MIDI, BSN notes, BSI
//! instructions; engine v2 MIDI), the MIDI toolkit's file writer and the 31-byte packer, recorded
//! before the gas optimizations ported from midi_fun_contract #14. Any change in output fails here.
use core::poseidon::poseidon_hash_span;
use koji::composition::beast_engine_v2::v3_score_midi_v2;
use koji::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, v3_score_instructions, v3_score_midi, v3_score_notes,
};
use koji::midi::output::{output_midi_object, to_felt252_array};
use koji::midi::types::{Message, Midi, NoteOff, NoteOn};

const V1: [(felt252, felt252, felt252); 5] = [
    (3093730228011006827138858803975496503036203856632346988412808275737308233072, 3018258821528678246599153672422309987893441027227521263151554037372610937509, 1255892598612031978023965457963772080033397212817343196536450631634705597880),
    (3386330419759330338756206255497155895000757494329707559246240606862673662251, 367567575647676028965117577493997631219671086775116230759379684679349936890, 3338636033910253135259791145983150344502700776844565640430808922687585078835),
    (3128845292721188649204298685401845579008325346273540833402396629679088814079, 226756691613719673891308440509898770769505769915943547383352000367024101219, 1863020470774082648423466217605121472015513226221005792878594835886457982852),
    (2293669295340203774746850874199168101732527836757703914189577098193694469090, 3416732683722665325828697779956440491592685631107584540494741824661115593209, 3517871608368549379434294765340509672557522313765991201957414306378874017386),
    (2180474285674570212949842986590918143099808983523675967611446835003474377528, 2007224625639744066206300527199069152630220637354515716045168729929487510673, 1232712827978292237114904054182018496887436649943449836221379439424845211107),
];
const V2: [felt252; 5] = [
    1915847883013310087303617772467114275372989169857983396393108444605117487157,
    998782374358251225262633771159719465677492563088084348498584480280134651079,
    3551873985236838069487011101110560344189176430523262964898408963660222684026,
    3156484683891447068362521177266151542437204545224114943003491082837560082146,
    2638045865804004191211467358453678616277978151628271013168836838422770140897,
];
const PACK: [felt252; 8] = [
    2384960345383653703825803024708982182127528589318022519244349682493582074337,
    1767910318038252128880064922196658030631735937809069784055613913369286380375,
    763313091946513148498991379903925215847657350517286545187051370364665646502,
    1573268099316797233014171831778776621917853445216192230997860639007320598998,
    464892004556243725504977805129540082799620603955645493188797637238348215965,
    551286814759037702802850424640722004215223371235918986351908483726399943549,
    166766843850110381387070957885358286092723114887683398971446223539097077755,
    53155610494201765958143175021016800805429735020243870276030075934851661889,
];

fn h(x: Span<felt252>) -> felt252 {
    poseidon_hash_span(x)
}

fn bytes_felts(b: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    for x in b {
        out.append((*x).into());
    }
    out
}

fn beasts() -> Array<(PackableBeastV3, BeastV3LiveState)> {
    array![
        (
            PackableBeastV3 { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 },
            BeastV3LiveState { adventurers_killed: 40, scars: 9, summit_held_seconds: 90000, rank: 1, species_count: 954 },
        ),
        (
            PackableBeastV3 { id: 6, prefix: 12, suffix: 4, level: 30, health: 120, shiny: 1, animated: 1, tier: 2, beast_type: 0 },
            BeastV3LiveState { adventurers_killed: 3, scars: 1, summit_held_seconds: 0, rank: 500, species_count: 954 },
        ),
        (
            PackableBeastV3 { id: 11, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 0, animated: 0, tier: 3, beast_type: 0 },
            BeastV3LiveState { adventurers_killed: 900, scars: 40, summit_held_seconds: 0, rank: 0, species_count: 1 },
        ),
        (
            PackableBeastV3 { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 0, tier: 1, beast_type: 2 },
            BeastV3LiveState { adventurers_killed: 100000, scars: 3000, summit_held_seconds: 0, rank: 2, species_count: 40 },
        ),
        (
            PackableBeastV3 { id: 75, prefix: 30, suffix: 6, level: 64, health: 300, shiny: 0, animated: 1, tier: 5, beast_type: 2 },
            BeastV3LiveState { adventurers_killed: 7, scars: 70, summit_held_seconds: 0, rank: 30, species_count: 300 },
        ),
    ]
}

#[test]
#[available_gas(1000000000000)]
fn golden_engine_v1_outputs() {
    let mut i: u32 = 0;
    for (b, l) in beasts() {
        let (m, n, ins) = *V1.span().at(i);
        assert_eq!(h(v3_score_midi(b, l).span()), m);
        assert_eq!(h(v3_score_notes(b, l).span()), n);
        assert_eq!(h(v3_score_instructions(b, l).span()), ins);
        i += 1;
    }
}

#[test]
#[available_gas(1000000000000)]
fn golden_engine_v2_midi() {
    let mut i: u32 = 0;
    for (b, l) in beasts() {
        assert_eq!(h(v3_score_midi_v2(b, l).span()), *V2.span().at(i));
        i += 1;
    }
}

#[test]
#[available_gas(1000000000000)]
fn golden_toolkit_writer_and_packer() {
    // note times in microseconds chosen so the deltas cross every VLQ length
    let times: Array<u64> = array![0, 0, 1, 127, 128, 255, 16383, 16384, 30000, 2097151, 2097152, 9000000, 268435455];
    let mut events: Array<Message> = array![];
    let mut t: u64 = 0;
    let mut k: u32 = 0;
    for d in times {
        t += d;
        let note: u8 = (40 + k % 40).try_into().unwrap();
        events.append(Message::NOTE_ON(NoteOn { channel: 0, note, velocity: 90, time: t }));
        events.append(Message::NOTE_OFF(NoteOff { channel: 0, note, velocity: 64, time: t + d / 2 + 1 }));
        k += 1;
    }
    let midi = Midi { events: events.span() };
    let bytes = output_midi_object(@midi);
    assert_eq!(bytes.len(), 159);
    assert_eq!(h(bytes_felts(bytes.span()).span()), 2881468803950920285925564175739556053159616148390658660656472140555491644845);
    let mut k: u32 = 0;
    for n in array![0_u32, 1, 30, 31, 32, 62, 63, 100] {
        let mut a: Array<u8> = array![];
        let mut j: u32 = 0;
        while j < n {
            a.append(((j * 37 + 11) % 256).try_into().unwrap());
            j += 1;
        }
        assert_eq!(h(to_felt252_array(a).span()), *PACK.span().at(k));
        k += 1;
    }
}
