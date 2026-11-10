# bitf.companion-ulanzi.dial

**Ulanzi D100H Dial Creative Controller → Bitfocus Companion — without the official Ulanzi Studio app.**

## Status

Prototype (macOS). The bridge turns every dial press and rotation into Bitfocus Companion remote-control commands, including real rotary actions on the knob. A Linux port is planned.

## How it works

```
Ulanzi D100H ──BLE HID──▶ d100h-bridge (macOS, IOHIDManager) ──UDP 51235──▶ Bitfocus Companion
                                                                        LOCATION … PRESS / ROTATE-LEFT / ROTATE-RIGHT
```

- The D100H is a Bluetooth LE HID device (KEHWIN "Dial Lite", VID `0xFFF1`, PID `0x0082`). Without Ulanzi Studio it falls back to a fixed layout: knob = volume/mute, top keys = media keys, side keys = Cmd+C / Cmd+V / Cmd+Z / Cmd+Shift+Z. See [docs/protocol-d100h.md](docs/protocol-d100h.md).
- macOS exposes all of those HID elements to normal processes (unlike Windows, which hides the keyboard-page keys), so no Ulanzi software is needed at all.
- Companion's remote-control API supports rotation triggers natively (`LOCATION <page>/<row>/<column> ROTATE-RIGHT`), sent over UDP `51235` (TCP listens on `51234`), newline-terminated. See [docs/architecture.md](docs/architecture.md).

## Requirements

- macOS 12+ with Xcode command line tools (`xcode-select --install`)
- Ulanzi D100H paired via Bluetooth (device name "Ulanzi Dial")
- Bitfocus Companion running on the same machine or reachable by IP
- Ulanzi Studio must **not** be running while the bridge runs (it holds the device)

## Quick start

```bash
cd bridge/macos
make
./d100h-bridge --debug
```

1. Pair the dial in macOS Bluetooth settings.
2. Run the bridge. Grant **Input Monitoring** permission when prompted (System Settings → Privacy & Security → Input Monitoring), then run again.
3. Turn the knob: `--debug` prints every HID element. Rotation should show `usagePage=0x0C usage=0xE9` (clockwise) or `0xEA` (counter-clockwise).
4. In Companion, place buttons at the mapped grid locations (defaults below) and enable rotary actions on the button used by the knob.
5. Drop `--debug` once everything works.

If the knob direction feels reversed, pass `--invert-knob`.

## Default mapping

| Control | HID (offline) | Bridge event | Default target |
| --- | --- | --- | --- |
| Knob clockwise | Consumer 0xE9 | knobRotateRight | 1/1/1 (rotary) |
| Knob counter-clockwise | Consumer 0xEA | knobRotateLeft | 1/1/1 (rotary) |
| Knob press | Consumer 0xE2 (mute) | knobPress | 1/1/1 (PRESS) |
| Top left | Consumer 0xB6 (prev) | topPrev | 1/1/2 |
| Top middle | Consumer 0xCD (play/pause) | topPlay | 1/1/3 |
| Top right | Consumer 0xB5 (next) | topNext | 1/1/4 |
| Side left-bottom | Keyboard Cmd+C | sideCopy | 1/2/2 |
| Side left-second | Keyboard Cmd+V | sidePaste | 1/2/3 |
| Side right-bottom | Keyboard Cmd+Z | sideUndo | 1/2/4 |
| Side right-second | Keyboard Cmd+Shift+Z | sideRedo | 1/2/5 |

## Configuration

`--host <ip>` (default `127.0.0.1`), `--port <udp-port>` (default `51235`), `--config <file.json>`, `--invert-knob`, `--debug`. A full example lives at [docs/config.example.json](docs/config.example.json). Every control can point at any button location via `page`/`row`/`column`; use `"action": "rotary"` for locations driven by the knob.

## Troubleshooting

- **Nothing arrives in Companion:** check Input Monitoring permission; close Ulanzi Studio; verify Companion's UDP port 51235 (TCP 51234) and any firewall; `--debug` should print raw HID elements while you interact with the dial.
- **Double triggers:** open an issue with the `--debug` output so the edge detection can be adjusted.

## Roadmap

- [ ] Linux port of the bridge (likely Go on top of [ftl/hamdial](https://github.com/ftl/hamdial) or Python following [rGnng/UlanziD100HProtocol](https://github.com/rGnng/UlanziD100HProtocol))
- [ ] Dial-side feedback (key LEDs, haptics) via the reverse-engineered TEA vendor BLE channel documented by [bitboxx/ulanzi-d100h](https://github.com/bitboxx/ulanzi-d100h)
- [ ] OSC remote module for Companion, following the official [module development guide](https://companion.free/for-developers/module-development/module-development-101/)

## Docs

- [docs/protocol-d100h.md](docs/protocol-d100h.md) — device identity, HID element map, vendor BLE protocol
- [docs/architecture.md](docs/architecture.md) — decisions and the verified Companion remote-control API
- [docs/setup-guide-de.html](docs/setup-guide-de.html) — German step-by-step setup guide (including the Ulanzi Studio fallback route)

## Credits

This project stands on community reverse-engineering: [brendanwelsh/ulanzi-d100h-homebrew](https://github.com/brendanwelsh/ulanzi-d100h-homebrew), [bitboxx/ulanzi-d100h](https://github.com/bitboxx/ulanzi-d100h), [rGnng/UlanziD100HProtocol](https://github.com/rGnng/UlanziD100HProtocol), [10on/ulanzi-d100h-light](https://github.com/10on/ulanzi-d100h-light), [toml-sys/d100h-screenstudio-mac](https://github.com/toml-sys/d100h-screenstudio-mac), [ftl/hamdial](https://github.com/ftl/hamdial).

## License

MIT
