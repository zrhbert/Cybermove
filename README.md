# Cybermove

A macOS monitor for the Cybermove MIDI output of
[Realtimer](https://github.com/zrhbert/realtimer) (RTM 4). Cybermove was
originally an Atari ST program, the standalone build of Realtimer's CMI and
CMO modules. This project shows the same kind of display on the Mac, fed by
the MIDI data Realtimer sends, either from Hatari or from an Atari connected
to the Mac through a MIDI interface.

Scope for now: **receive and display only.** The structure leaves room for
sending data back to the Atari later (see Design).

## Wire format

Taken from Realtimer's CMO module (`src/cmo.c`) and confirmed against a
capture of Realtimer playing in Hatari (`Tests/.../Fixtures/realtimer-play.bin`).

| Part | Meaning |
|---|---|
| Message | Note On |
| Channel | which CMI system (Realtimer defaults to MIDI channels 15 and 16) |
| Pitch | `signal * 4 + axis`, so 32 signals per system |
| Axis | 0 X, 1 Y, 2 Z, 3 volume |
| Velocity | the value; coordinates are `velocity - 64` (range -64 to +63), volume is raw |
| MIDI Stop | resets every coordinate and volume to zero |

Note Off, Clock and everything else are ignored, as in CMO. Velocity 0 is a
real value, not a note off. Realtimer sends every message with its own status
byte (no running status) and two Stop messages per stop.

## The app

`swift run Cybermove` opens the window and starts following `/tmp/cybermove.fifo`
(it creates the FIFO). The left side lists the 32 signals of the chosen system.
The right side is a grid of cubes laid out like Realtimer's CMO window, in the
same four graphics modes: mono (one signal per cube, a line from the centre),
stereo (pairs joined), quadro and okto (four or eight signals on one line).
The channel buttons choose which CMI system is shown.

## Try it with Hatari

Hatari needs a MIDI input as well, otherwise it disables MIDI completely. The
output FIFO blocks until a reader opens it, so start the decoder first.

```sh
mkfifo /tmp/cybermove.fifo
swift run cybermove-decode /tmp/cybermove.fifo --events &
hatari ... --midi-in /dev/null --midi-out /tmp/cybermove.fifo realtim5.prg
```

Only Hatari builds with MIDI file support take these options; the build in the
Atari ST Dev VS Code extension has none. Decode a recording instead with
`swift run cybermove-decode capture.bin`. Pass `--channels 14,15` to choose the
0-based channels of the two systems.

## Layout

| Path | Contents |
|---|---|
| `Sources/CybermoveCore` | MIDI parser, CMO-style decoder, projection math, byte sources. No UI. |
| `Sources/CybermoveUI` | SwiftUI table, cube grid and the controller that follows a FIFO |
| `Sources/Cybermove` | the macOS app |
| `Sources/cybermove-decode` | command-line decoder for captures and live FIFOs |
| `Sources/cybermove-snapshot` | renders the window to a PNG from a capture, for checking the display |
| `Tests/CybermoveCoreTests` | parser and decoder tests, plus the real capture |

`swift test` runs everything.

## Design

The decoder only depends on a byte stream (`MidiByteSource`). The Hatari FIFO
is the first source; a CoreMIDI source for real hardware is next, and a
bidirectional port can later sit beside it without touching the decoder.

## Roadmap

1. Core library and command-line decoder (done).
2. SwiftUI app with the coordinate table and the CMO-style cube grid (done).
3. CoreMIDI source for a physical connection, and an Xcode wrapper for a proper app bundle.
4. Display options from Realtimer's setup: crosshairs, perspective angles, per-signal line switches.
5. Later: sending data to the Atari (transport, MMC, MTC position).
