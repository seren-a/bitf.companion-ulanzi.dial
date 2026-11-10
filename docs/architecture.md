# Architecture and decisions

## Goal

Drive Bitfocus Companion with the Ulanzi D100H dial (knob + 7 keys) without
running the official Ulanzi Studio app, and keep Companion as the single hub
for buttons, actions and (later) the OSC remote module.

## Decisions (November 2026)

1. **macOS first, Linux second.** On macOS all HID elements of the dial are
   readable; on Linux `hidraw`/`evdev` gives the same access. Windows hides the
   keyboard-page keys, so it is not the primary target.
2. **No Ulanzi Studio.** The 1 GB Chromium-based app stays off the machine; the
   dial's factory HID layout is read directly. The official Studio route
   (community `com.ulanzi.companion` plugin) remains a documented fallback in
   the setup guide.
3. **Companion stays the hub.** Native dial apps exist
   ([TimmySheep/ulanzidial-native](https://github.com/TimmySheep/ulanzidial-native),
   [petitstrawberry/dial-studio](https://github.com/petitstrawberry/dial-studio)),
   but they replace Ulanzi Studio, not Companion; the bridge keeps everything
   in one place.

## Verified Companion remote-control API

From the official documentation (v4.1; same commands in v5.x):

- **UDP port 51235**, TCP port 51234. Commands are newline-terminated
  (`\n` or `\r\n`).
- Relevant commands:
  - `LOCATION <page>/<row>/<column> PRESS` — press and release a button
  - `LOCATION <page>/<row>/<column> DOWN` / `UP`
  - `LOCATION <page>/<row>/<column> ROTATE-LEFT` / `ROTATE-RIGHT` — trigger a
    rotation of the button/encoder
  - `LOCATION <page>/<row>/<column> SET-STEP <step>`
  - `CUSTOM-VARIABLE <name> SET-VALUE <value>`
  - `SURFACE <surface id> PAGE-SET <page number>` / `PAGE-UP` / `PAGE-DOWN`

Consequence: the plain remote-control API already covers rotary actions, so
the prototype needs no Companion Satellite protocol and no custom surface
module to trigger button rotations.

## Current design (prototype)

```
Ulanzi D100H (BLE HID, factory layout)
        │
        ▼  IOHIDManager input value callbacks
d100h-bridge (Swift, macOS)
        │  translate element -> event -> LOCATION command
        ▼  UDP datagrams, port 51235
Bitfocus Companion
        ├─ button grid: buttons at the mapped page/row/column
        └─ knob button: rotary steps enabled (ROTATE-LEFT / ROTATE-RIGHT)
```

The mapping from dial events to grid locations lives in a JSON config
(`docs/config.example.json`), so any button layout can be targeted without
touching code.

## Limitations and future work

- **No dial-side feedback yet.** The HID factory layout is input-only; key LEDs
  and haptics require the TEA vendor BLE channel (see
  [protocol-d100h.md](protocol-d100h.md)). A later milestone is a bidirectional
  bridge that lights the dial keys from Companion button colors.
- **Surface module alternative.** Companion ≥ 4.3 has a surface module system
  ([bitfocus/companion-surface-midi](https://github.com/bitfocus/companion-surface-midi)
  is the pattern to follow). A first-class `ulanzi-d100h` surface would give
  automatic page handling and visual feedback without the remote-control API.
- **Linux port.** Same JSON mapping, different input layer: reuse
  [ftl/hamdial](https://github.com/ftl/hamdial) (Go, `hidraw`) or the Python
  tooling from [rGnng/UlanziD100HProtocol](https://github.com/rGnng/UlanziD100HProtocol).
- **OSC remote module.** After the bridge is validated, the next build is a
  Companion connection module that speaks OSC to the target device, following
  the official module structure (`package.json`, `companion/manifest.json`,
  `companion/HELP.md`, module class with `init`, `configUpdated`, `destroy`).
