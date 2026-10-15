# Koji: A Cairo library for Autonomous Music

Koji is Casey Wescott's generative-music library in Cairo: MIDI tools, harmony, counterpoint,
rhythm and form, written for onchain composition. It was developed inside
[midi_fun_contract](https://github.com/caseywescott/midi_fun_contract) until October 2026, when that
repository narrowed to the Beasts V3 sound system; this repository carries Koji on, with its full
history (the last commit there is tagged `archive/koji`).

## What's here

| Path | What it is | Toolchain |
|---|---|---|
| `src/` | The Koji Cairo library (`scarb build`, `scarb test`) | scarb 2.11.4 (`.tool-versions`) |
| `src/composition/` | Harmony (Barry Harris, jazz, neo-Riemannian, harmonic walk, voice leading), counterpoint and canons (rules, entry-lag, invertible, stretto, countersubject, transformational counterpoint, canon fitter), rhythm (Euclidean, timelines, phase, tilings, Messiaen modes, symmetry), Ligeti-style textures, motif algebra and form, baroque improvisation, ornamentation v2, and the Beast composer as it was before it moved out | |
| `src/midi/` | The MIDI toolkit: events, modes, pitch, time, Euclidean rhythm, velocity curves, voicings, MIDI-to-Cairo output | |
| `offchain/beast-sound/` | Beast Engine v1 and v2 in JavaScript (`engine.js`, `engine_v2.js`), the BSN/BSI note formats and a CLI; `npm test` | Node 20+ |
| `web/beast_sound/` | The Beast Sound simulator page (plays Engine v1 and v2 in the browser) | |
| `python/`, `typescript/`, `Makefile` | MIDI to Cairo/JSON converters and the Cairo-to-MIDI parser | Python 3, Node |
| `scripts/`, `demos/`, `fixtures/`, `data/`, `example/` | Demo MIDI generators, research catalogs (harmony, rhythm, tilings), the canon fitter | |
| `docs/` | The composition guide, the canon-fitter and transformational-counterpoint specs, the Loot Survivor Beast specs | |

The Beast Sound system that ships onchain (the composer, `BeastMidiProvider`, the sound page and
the lab) lives in midi_fun_contract, not here.

## Features

- **Euclidean Rhythm Generation**: Generate musical patterns using Bjorklund's algorithm
- **Velocity Curve Processing**: Apply dynamic velocity transformations to MIDI events
- **MIDI Event Handling**: Full support for NoteOn, NoteOff, SetTempo, and other MIDI messages
- **Cairo Code Generation**: Generate clean Cairo code from MIDI data structures
- **Cairo to MIDI Conversion**: Convert Cairo code back to playable MIDI files
- **Python Integration**: Convert MIDI files to Cairo structs and JSON formats
- **TypeScript Parser**: Parse Cairo MIDI events back to standard MIDI format

## Quick Start

[Cairo Music Composition Guide](docs/composing.md) - Complete workflow for composing music with Cairo and Koji utilities

### Cairo Code Generation

Generate clean Cairo code from MIDI data:

```bash
# Using the automated script (recommended)
./scripts/generate_cairo_output.sh

# Or manually with redirection
SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | \
grep -v "running\|test\|gas usage\|test result" > my_midi.cairo
```

### Cairo to MIDI Conversion

Convert Cairo code back to playable MIDI files:

```bash
# Generate both Cairo code and MIDI file
./scripts/generate_cairo_and_midi.sh

# Generate only Cairo code
./scripts/generate_cairo_and_midi.sh --cairo-only

# Generate only MIDI from existing Cairo file
./scripts/generate_cairo_and_midi.sh --midi-only

# Use custom filenames
./scripts/generate_cairo_and_midi.sh --cairo-output my_music.cairo --midi-output my_music.mid
```

### Running Tests

```bash
# Run all tests
scarb test

# Run specific test
scarb test -- --filter midi_to_cairo_file_output_test

# Run with quiet output
SCARB_UI_VERBOSITY=quiet scarb test
```

### Python MIDI Conversion

```bash
# Convert MIDI to Cairo struct
python3 python/cli.py input.mid output.cairo --format cairo

# Convert MIDI to JSON
python3 python/cli.py input.mid output.json --format json
```

## Project Structure

```
koji-cairo/
├── src/
│   ├── midi/           # Core MIDI functionality
│   │   ├── core.cairo      # Main MIDI processing
│   │   ├── euclidean.cairo # Euclidean rhythm generation
│   │   ├── instruments.cairo # Instrument handling
│   │   ├── modes.cairo     # Musical modes
│   │   ├── output.cairo    # Output formatting
│   │   ├── pitch.cairo     # Pitch calculations
│   │   ├── time.cairo      # Time quantization
│   │   ├── types.cairo     # MIDI type definitions
│   │   ├── velocitycurve.cairo # Velocity processing
│   │   └── voicings.cairo  # Chord voicings
│   └── tests/
│       └── midi_2_cairo_print.cairo # Cairo code generation tests
├── python/             # Python MIDI conversion tools
├── typescript/         # TypeScript MIDI parsing and conversion
├── scripts/
│   ├── generate_cairo_output.sh # Cairo code generation
│   └── generate_cairo_and_midi.sh # Full Cairo to MIDI pipeline
└── docs/               # Documentation
```

## Documentation

- [Cairo Music Composition Guide](docs/composing.md) - Complete workflow for composing music with Cairo and Koji utilities

## Development

### Prerequisites

- Scarb (Cairo package manager)
- Python 3.7+
- Node.js (for TypeScript tools)

### Setup

```bash
# Install Scarb dependencies
scarb build

# Install Python dependencies
cd python && pip install -r requirements.txt

# Install TypeScript dependencies
cd typescript && npm install
```

Autonomous Music library based on previous [work](https://github.com/caseywescott/MusicTools-StarkNet) made by Casey Wescott.

# Midi Conversion

Convert Midi to JSON format:

```bash
make convert-json MIDI_FILE="path/to/midi/file.mid" OUTPUT_FILE="path/to/output"
```

Convert to Cairo format:

```bash
make convert-cairo MIDI_FILE="path/to/midi/file.mid" OUTPUT_FILE="path/to/output"
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
