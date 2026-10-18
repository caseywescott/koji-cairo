use core::array::{ArrayTrait, SpanTrait};
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::math::Time;
use koji::midi::types::{Message, Midi};

#[derive(Drop)]
struct MidiOutput {
    data: Array<u8>,
}

trait MidiOutputTrait {
    fn new() -> MidiOutput;
    fn append_byte(ref self: MidiOutput, value: u8);
    fn append_bytes(ref self: MidiOutput, values: Array<u8>);
    fn len(self: @MidiOutput) -> usize;
    fn get_data(self: @MidiOutput) -> Array<u8>;
}

impl MidiOutputImpl of MidiOutputTrait {
    fn new() -> MidiOutput {
        MidiOutput { data: ArrayTrait::new() }
    }

    fn append_byte(ref self: MidiOutput, value: u8) {
        self.data.append(value);
    }

    fn append_bytes(ref self: MidiOutput, mut values: Array<u8>) {
        loop {
            match values.pop_front() {
                Option::Some(value) => { self.data.append(value); },
                Option::None => { break; },
            };
        }
    }

    fn len(self: @MidiOutput) -> usize {
        self.data.len()
    }

    fn get_data(self: @MidiOutput) -> Array<u8> {
        let mut result = ArrayTrait::new();
        let mut data = self.data.span();
        loop {
            match data.pop_front() {
                Option::Some(value) => { result.append(*value); },
                Option::None => { break; },
            };
        }
        result
    }
}

/// Export MIDI object to binary MIDI file format
pub fn output_midi_object(midi: @Midi) -> Array<u8> {
    let mut output = MidiOutputTrait::new();

    // Add MIDI header chunk
    output.append_bytes(array![0x4D, 0x54, 0x68, 0x64]); // MThd
    output.append_bytes(array![0x00, 0x00, 0x00, 0x06]); // Length
    output.append_bytes(array![0x00, 0x00]); // Format 0
    output.append_bytes(array![0x00, 0x01]); // Number of tracks
    output.append_bytes(array![0x01, 0xE0]); // Division (480 PPQN)

    // Add track chunk header
    output.append_bytes(array![0x4D, 0x54, 0x72, 0x6B]); // MTrk

    // For simplicity, we'll create the track content first, then add length
    let mut track_output = MidiOutputTrait::new();

    let mut prev_time: Time = 0;
    let mut ev = *midi.events;

    loop {
        match ev.pop_front() {
            Option::Some(event) => {
                match event {
                    Message::NOTE_ON(note) => {
                        let delta: u32 = if *note.time >= prev_time {
                            (*note.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *note.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0x90 + (*note.channel % 16));
                        track_output.append_byte(*note.note);
                        track_output.append_byte(*note.velocity);
                    },
                    Message::NOTE_OFF(note) => {
                        let delta: u32 = if *note.time >= prev_time {
                            (*note.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *note.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0x80 + (*note.channel % 16));
                        track_output.append_byte(*note.note);
                        track_output.append_byte(*note.velocity);
                    },
                    Message::SET_TEMPO(tempo) => {
                        let time = match tempo.time {
                            Option::Some(t) => *t,
                            Option::None => prev_time,
                        };
                        let delta: u32 = if time >= prev_time {
                            (time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = time;

                        write_variable_length(delta, ref track_output);
                        track_output.append_bytes(array![0xFF, 0x51, 0x03]);

                        let tempo_val: u32 = (*tempo.tempo).into();
                        track_output.append_byte((tempo_val / 65536).try_into().unwrap());
                        track_output.append_byte(((tempo_val / 256) % 256).try_into().unwrap());
                        track_output.append_byte((tempo_val % 256).try_into().unwrap());
                    },
                    Message::PROGRAM_CHANGE(pc) => {
                        let delta: u32 = if *pc.time >= prev_time {
                            (*pc.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *pc.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0xC0 + (*pc.channel % 16));
                        track_output.append_byte(*pc.program);
                    },
                    Message::CONTROL_CHANGE(cc) => {
                        let delta: u32 = if *cc.time >= prev_time {
                            (*cc.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *cc.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0xB0 + (*cc.channel % 16));
                        track_output.append_byte(*cc.control);
                        track_output.append_byte(*cc.value);
                    },
                    // Handle other message types as pass-through
                    _ => {},
                }
            },
            Option::None => { break; },
        };
    }

    // Write End of Track
    track_output.append_bytes(array![0x00, 0xFF, 0x2F, 0x00]);

    // Add track length
    let track_length = track_output.len();
    output.append_byte((track_length / 16777216).try_into().unwrap());
    output.append_byte(((track_length / 65536) % 256).try_into().unwrap());
    output.append_byte(((track_length / 256) % 256).try_into().unwrap());
    output.append_byte((track_length % 256).try_into().unwrap());

    // Add track data
    output.append_bytes(track_output.get_data());

    output.get_data()
}

/// A MIDI variable-length quantity, big-endian 7-bit groups with the continuation bit on all but
/// the last. Nearly every delta is 1 or 2 bytes, so those two are straight-line code; the longer
/// forms are a loop on purpose, because a function without a loop is charged for its most
/// expensive path on every call.
fn write_variable_length(value: u32, ref output: MidiOutput) {
    if value < 0x80 {
        output.append_byte(value.try_into().unwrap());
    } else if value < 0x4000 {
        let (high, low) = DivRem::div_rem(value, 0x80);
        output.append_byte((0x80 + high).try_into().unwrap());
        output.append_byte(low.try_into().unwrap());
    } else {
        // the place of the highest group: 128^2 to 128^4 (a u32 needs up to five groups)
        let mut place: u32 = 0x4000;
        while value / place >= 0x80 {
            place *= 0x80;
        };
        let mut rest = value;
        while place > 1 {
            let (group, below) = DivRem::div_rem(rest, place.try_into().unwrap());
            output.append_byte((0x80 + group).try_into().unwrap());
            rest = below;
            place /= 0x80;
        };
        output.append_byte(rest.try_into().unwrap());
    }
}

/// 31 bytes as one big-endian word. Straight-line: a loop pays a call, a gas check and a checked
/// counter per byte; this is two steps a byte.
#[cairofmt::skip]
fn pack_word(chunk: Box<[u8; 31]>) -> felt252 {
    let [
        b0, b1, b2, b3, b4, b5, b6, b7,
        b8, b9, b10, b11, b12, b13, b14, b15,
        b16, b17, b18, b19, b20, b21, b22, b23,
        b24, b25, b26, b27, b28, b29, b30,
    ] = chunk.unbox();
    let word: felt252 = b0.into();
    let word = word * 0x100 + b1.into();
    let word = word * 0x100 + b2.into();
    let word = word * 0x100 + b3.into();
    let word = word * 0x100 + b4.into();
    let word = word * 0x100 + b5.into();
    let word = word * 0x100 + b6.into();
    let word = word * 0x100 + b7.into();
    let word = word * 0x100 + b8.into();
    let word = word * 0x100 + b9.into();
    let word = word * 0x100 + b10.into();
    let word = word * 0x100 + b11.into();
    let word = word * 0x100 + b12.into();
    let word = word * 0x100 + b13.into();
    let word = word * 0x100 + b14.into();
    let word = word * 0x100 + b15.into();
    let word = word * 0x100 + b16.into();
    let word = word * 0x100 + b17.into();
    let word = word * 0x100 + b18.into();
    let word = word * 0x100 + b19.into();
    let word = word * 0x100 + b20.into();
    let word = word * 0x100 + b21.into();
    let word = word * 0x100 + b22.into();
    let word = word * 0x100 + b23.into();
    let word = word * 0x100 + b24.into();
    let word = word * 0x100 + b25.into();
    let word = word * 0x100 + b26.into();
    let word = word * 0x100 + b27.into();
    let word = word * 0x100 + b28.into();
    let word = word * 0x100 + b29.into();
    let word = word * 0x100 + b30.into();
    word
}

/// Pack raw MIDI bytes for RPC transport (Koji PRD v0.2 §5.2).
/// Element `[0]` is `midi_bytes.len()`; each subsequent felt packs up to 31 bytes big-endian.
/// Must match `frontend/lib/packMidiToFelts.ts` and `deserializeFeltsToMidi`.
pub fn to_felt252_array(midi_bytes: Array<u8>) -> Array<felt252> {
    let mut bytes = midi_bytes.span();
    let mut result: Array<felt252> = array![bytes.len().into()];
    while let Option::Some(chunk) = bytes.multi_pop_front::<31>() {
        result.append(pack_word(*chunk));
    };
    if bytes.len() != 0 {
        let mut word: felt252 = 0;
        while let Option::Some(byte) = bytes.pop_front() {
            word = word * 0x100 + (*byte).into();
        };
        result.append(word);
    }
    result
}

/// The writer and the packer against their original definitions.
#[cfg(test)]
mod tests {
    use super::{MidiOutput, MidiOutputTrait, to_felt252_array, write_variable_length};

    fn reference_vlq(mut value: u32) -> Array<u8> {
        if value == 0 {
            return array![0];
        }
        let mut groups: Array<u8> = array![(value % 128).try_into().unwrap()];
        value = value / 128;
        while value != 0 {
            groups.append(((value % 128) + 128).try_into().unwrap());
            value = value / 128;
        };
        let mut out: Array<u8> = array![];
        let mut i = groups.len();
        while i != 0 {
            i -= 1;
            out.append(*groups.at(i));
        };
        out
    }

    fn reference_pack(bytes: Array<u8>) -> Array<felt252> {
        let total = bytes.len();
        let mut out: Array<felt252> = array![total.into()];
        let mut i: u32 = 0;
        while i < total {
            let mut val: u256 = 0;
            let mut j: u32 = 0;
            while j < 31 && i + j < total {
                val = val * 256 + (*bytes.at(i + j)).into();
                j += 1;
            };
            out.append(val.try_into().unwrap());
            i += 31;
        };
        out
    }

    #[test]
    #[available_gas(100000000000)]
    fn variable_length_is_the_original() {
    let mut vals: Array<u32> = array![];
    let mut v: u32 = 0;
    while v <= 0x4100 {
        vals.append(v);
        v += 1;
    };
    // every length boundary, and a spread across the whole range
    for b in array![0x1fffff_u32, 0x200000, 0x200001, 0xfffffff, 0x10000000, 0x10000001, 0x7fffffff, 0xffffffff] {
        vals.append(b);
    };
    let mut x: u32 = 0x4101;
    while x < 0x50000000 {
        vals.append(x);
        x = x * 3 + 7;
    };
        for value in vals {
            let mut out: MidiOutput = MidiOutputTrait::new();
            write_variable_length(value, ref out);
            assert!(out.get_data() == reference_vlq(value));
        };
    }

    #[test]
    #[available_gas(100000000000)]
    fn packing_is_the_original() {
        let mut n: u32 = 0;
        while n <= 130 {
            let mut a: Array<u8> = array![];
            let mut b: Array<u8> = array![];
            let mut j: u32 = 0;
            while j < n {
                let byte: u8 = ((j * 151 + n * 7 + 3) % 256).try_into().unwrap();
                a.append(byte);
                b.append(byte);
                j += 1;
            };
            assert!(to_felt252_array(a) == reference_pack(b));
            n += 1;
        };
    }
}
