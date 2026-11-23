#!/bin/bash
# Cyclic transformation demo: the theme, its Ravel-like finale, and the Debussy-like cycle.
# Run from the repository root: ./scripts/generate_cyclic_demo_midis.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p demos/cyclic
hex=$(SCARB_UI_VERBOSITY=quiet scarb test -- --include-ignored --filter cyclic_demo_midi_hex 2>&1 \
  | sed -n 's/.*CYCLIC_MIDI_HEX=\([0-9a-f]*\).*/\1/p' | head -1)
if [ -z "$hex" ]; then
  echo "no MIDI hex in test output" >&2
  exit 1
fi
printf '%s' "$hex" | xxd -r -p > demos/cyclic/cyclic_demo.mid
echo "Wrote demos/cyclic/cyclic_demo.mid ($(wc -c < demos/cyclic/cyclic_demo.mid | tr -d ' ') bytes)"
echo "  ch 0-1: theme, Ravel-like finale (contracted, D minor, 3+2)"
echo "  ch 2-5: Debussy-like seed, scherzo (pizzicato, x2/3), slow (whole-tone, x4), return"
