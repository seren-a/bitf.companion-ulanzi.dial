# Ulanzi D100H protocol notes

Everything needed to integrate the dial without the official Ulanzi Studio app.
Unofficial, gathered from community reverse-engineering (see Credits in the
[README](../README.md)).

## Device identity

| Property | Value |
| --- | --- |
| Product | Ulanzi D100H Dial Creative Controller |
| Bluetooth name | `Ulanzi Dial` |
| HID manufacturer / product | `KEHWIN` / `Dial Lite` |
| VID / PID | `0xFFF1` / `0x0082` |
| Transport | Bluetooth LE 5.1 (HID over GATT); USB-C is believed charge-only in older community reports, but newer work documents a wired USB protocol — verify on your unit |

## Behaviour: online vs offline mode

- Custom layouts are **never stored on the device**. Ulanzi Studio remaps the
  inputs in software while it runs; close it and the dial falls back to the
  factory layout below.
- The vendor BLE channel is **TEA-encrypted** (see below). Prior community
  efforts only saw heartbeat traffic there; the cipher is now public.

## HID elements (offline / factory layout)

Reported via IOHIDManager value callbacks on macOS:

| Control | Usage page | Usage | Meaning |
| --- | --- | --- | --- |
| Knob rotate clockwise | Consumer (0x0C) | 0xE9 | Volume increment |
| Knob rotate counter-clockwise | Consumer (0x0C) | 0xEA | Volume decrement |
| Knob press | Consumer (0x0C) | 0xE2 | Mute |
| Top left | Consumer (0x0C) | 0xB6 | Scan previous track |
| Top middle | Consumer (0x0C) | 0xCD | Play / pause |
| Top right | Consumer (0x0C) | 0xB5 | Scan next track |
| Side left-bottom | Keyboard (0x07) | 0x06 + modifier 0xE3 | Cmd+C |
| Side left-second | Keyboard (0x07) | 0x19 + modifier 0xE3 | Cmd+V |
| Side right-bottom | Keyboard (0x07) | 0x1D + modifier 0xE3 | Cmd+Z |
| Side right-second | Keyboard (0x07) | 0x1D + modifiers 0xE3, 0xE2 | Cmd+Shift+Z |

Platform notes:

- **macOS**: every element above is readable by a normal process
  (grant *Input Monitoring* when prompted). Close Ulanzi Studio first.
- **Windows**: the OS hides the keyboard-page keys from applications, so only
  the dial and the three media keys are visible there.
- **Linux**: all keys are readable via `hidraw`/`evdev` (see
  [ftl/hamdial](https://github.com/ftl/hamdial) and
  [gunnoej5/dialtone](https://github.com/gunnoej5/dialtone)).

## Vendor BLE protocol (TEA)

Documented and implemented by the community:

- GATT service `0x1971`, characteristics `FD01` (write) and `FD00` (notify).
- 20-byte frames consisting of two 8-byte **TEA** blocks.
- Command set includes GET/SET commands, a button function table, input-event
  format, haptics control, sleep timer, serial query and heartbeat.
- References:
  - [bitboxx/ulanzi-d100h](https://github.com/bitboxx/ulanzi-d100h) — full
    protocol spec (`PROTOCOL.md`) plus a macOS CoreBluetooth reference client
    (`ulanzi-ctl`) that coexists with the OS HID connection.
  - [rGnng/UlanziD100HProtocol](https://github.com/rGnng/UlanziD100HProtocol) —
    Python tooling, Linux event mappings, ESP32 codec, regression tests.
  - [kriomant/ulanzi-d100h](https://github.com/kriomant/ulanzi-d100h) —
    Rust/Python codecs verified against firmware 1.3.8.1.

This channel is the future path for dial-side feedback: key LED colours and
haptics driven from the bridge.
