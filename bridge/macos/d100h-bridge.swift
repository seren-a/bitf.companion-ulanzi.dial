//
//  d100h-bridge.swift
//  Ulanzi D100H (Bluetooth HID) -> Bitfocus Companion (UDP remote control)
//
//  Part of bitf.companion-ulanzi.dial
//  Copyright (c) 2026 Isabella Forster — MIT License
//
//  Build : make   (or: swiftc -O -o d100h-bridge d100h-bridge.swift)
//  Run   : ./d100h-bridge [--host 127.0.0.1] [--port 51235] [--config file.json]
//                         [--invert-knob] [--debug]
//
//  What it does
//  ------------
//  The Ulanzi D100H is a Bluetooth LE HID device (KEHWIN "Dial Lite",
//  VID 0xFFF1 / PID 0x0082). Without Ulanzi Studio running it falls back to
//  a fixed layout: knob = volume/mute, three top keys = media keys, four side
//  keys = Cmd+C / Cmd+V / Cmd+Z / Cmd+Shift+Z. macOS exposes every one of
//  those HID elements to normal processes, so no Ulanzi software is needed.
//
//  This bridge watches the device with IOHIDManager and translates each
//  press / rotation into a Companion remote-control command sent over UDP
//  (default port 51235), for example:
//
//      LOCATION 1/1/1 ROTATE-RIGHT
//
//  In Companion, point buttons at the same grid locations; the button used
//  by the knob should have rotary actions enabled.
//
//  Notes:
//  * Close Ulanzi Studio before running the bridge (it holds the device).
//  * Grant "Input Monitoring" permission when macOS asks for it.
//

import Foundation
import IOKit
import IOKit.hid

// MARK: - Configuration

struct LocationConfig: Codable {
    var page: Int = 1
    var row: Int = 1
    var column: Int = 1
    /// "press"  -> send "LOCATION p/r/c PRESS" when the key goes down
    /// "rotary" -> knob rotation sends ROTATE-LEFT / ROTATE-RIGHT,
    ///             knob press sends PRESS
    var action: String = "press"

    private enum CodingKeys: String, CodingKey {
        case page, row, column, action
    }

    init(page: Int = 1, row: Int = 1, column: Int = 1, action: String = "press") {
        self.page = page
        self.row = row
        self.column = column
        self.action = action
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 1
        column = try c.decodeIfPresent(Int.self, forKey: .column) ?? 1
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? "press"
    }
}

struct BridgeConfig: Codable {
    var host: String = "127.0.0.1"
    /// Companion UDP remote-control port (TCP listens on 51234)
    var port: UInt16 = 51235
    /// Swap knob rotation direction in case a unit reports it inverted
    var invertKnob: Bool = false
    var buttons: [String: LocationConfig] = BridgeConfig.defaultButtons

    static let defaultButtons: [String: LocationConfig] = [
        "knob": LocationConfig(page: 1, row: 1, column: 1, action: "rotary"),
        "topPrev": LocationConfig(page: 1, row: 1, column: 2),
        "topPlay": LocationConfig(page: 1, row: 1, column: 3),
        "topNext": LocationConfig(page: 1, row: 1, column: 4),
        "sideCopy": LocationConfig(page: 1, row: 2, column: 2),
        "sidePaste": LocationConfig(page: 1, row: 2, column: 3),
        "sideUndo": LocationConfig(page: 1, row: 2, column: 4),
        "sideRedo": LocationConfig(page: 1, row: 2, column: 5),
    ]

    private enum CodingKeys: String, CodingKey {
        case host, port, invertKnob, buttons
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "127.0.0.1"
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? 51235
        invertKnob = try c.decodeIfPresent(Bool.self, forKey: .invertKnob) ?? false
        buttons = try c.decodeIfPresent([String: LocationConfig].self, forKey: .buttons) ?? BridgeConfig.defaultButtons
    }
}

// MARK: - Companion UDP sender

final class CompanionSender {
    private let sock: Int32
    private let addr: sockaddr_in

    init(host: String, port: UInt16) throws {
        sock = socket(AF_INET, SOCK_DGRAM, 0)
        guard sock >= 0 else {
            throw NSError(domain: "d100h-bridge", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not create UDP socket"])
        }
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &a.sin_addr) == 1 else {
            close(sock)
            throw NSError(domain: "d100h-bridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid IPv4 host: \(host)"])
        }
        addr = a
    }

    func send(_ command: String) {
        var a = addr
        let payload = Array((command + "\n").utf8)
        payload.withUnsafeBufferPointer { buf in
            withUnsafePointer(to: &a) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = sendto(sock, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}

// MARK: - HID watcher

final class DialWatcher {
    private let manager: IOHIDManager
    private let sender: CompanionSender
    private let config: BridgeConfig
    private let debug: Bool
    /// Keyboard-page modifiers currently held (HID usages 0xE0...0xE7)
    private var modifiers = Set<Int>()

    init(sender: CompanionSender, config: BridgeConfig, debug: Bool) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.sender = sender
        self.config = config
        self.debug = debug
    }

    func start() {
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: 0xFFF1,
            kIOHIDProductIDKey as String: 0x0082,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        let ctx = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, _ in
            print("[bridge] dial connected")
        }, ctx)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, _ in
            print("[bridge] dial disconnected")
        }, ctx)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context = context, let value = value else { return }
            Unmanaged<DialWatcher>.fromOpaque(context).takeUnretainedValue().handleValue(value)
        }, ctx)
    }

    private func handleValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let raw = IOHIDValueGetIntegerValue(value)
        let pressed = raw != 0

        if debug {
            print(String(format: "[debug] usagePage=0x%02X usage=0x%02X value=%d", page, usage, raw))
        }

        switch page {
        case 0x0C: handleConsumer(usage: usage, pressed: pressed)
        case 0x07: handleKeyboard(usage: usage, pressed: pressed)
        default: break // vendor heartbeat frames etc.
        }
    }

    private func handleConsumer(usage: Int, pressed: Bool) {
        guard pressed else { return }
        switch usage {
        case 0xE9: dispatch("knobRotateRight")
        case 0xEA: dispatch("knobRotateLeft")
        case 0xE2: dispatch("knobPress")
        case 0xB6: dispatch("topPrev")
        case 0xCD: dispatch("topPlay")
        case 0xB5: dispatch("topNext")
        default: break
        }
    }

    private func handleKeyboard(usage: Int, pressed: Bool) {
        // Modifier keys arrive as their own elements on the keyboard page.
        if (0xE0...0xE7).contains(usage) {
            if pressed {
                modifiers.insert(usage)
            } else {
                modifiers.remove(usage)
            }
            return
        }
        guard pressed else { return }
        switch usage {
        case 0x06: dispatch("sideCopy")
        case 0x19: dispatch("sidePaste")
        case 0x1D:
            if modifiers.contains(0xE2) { // left shift held -> Cmd+Shift+Z
                dispatch("sideRedo")
            } else {
                dispatch("sideUndo")
            }
        default: break
        }
    }

    private func dispatch(_ event: String) {
        guard let loc = config.buttons[event] else {
            if debug { print("[bridge] no mapping for event '\(event)'") }
            return
        }
        let target = "LOCATION \(loc.page)/\(loc.row)/\(loc.column)"
        let rotary = loc.action == "rotary"
        let cw = config.invertKnob ? "ROTATE-LEFT" : "ROTATE-RIGHT"
        let ccw = config.invertKnob ? "ROTATE-RIGHT" : "ROTATE-LEFT"
        var command = "\(target) PRESS"
        switch event {
        case "knobRotateRight" where rotary: command = "\(target) \(cw)"
        case "knobRotateLeft" where rotary: command = "\(target) \(ccw)"
        default: break
        }
        sender.send(command)
        print("[bridge] \(event) -> \(command)")
    }
}

// MARK: - Main

func printHelp() {
    let name = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
    print("""
    \(name) — Ulanzi D100H to Bitfocus Companion bridge (macOS)

    Usage:
      \(name) [--host <ip>] [--port <udp-port>] [--config <file.json>]
              [--invert-knob] [--debug]

    Options:
      --host <ip>        Companion host (default 127.0.0.1)
      --port <port>      Companion UDP port (default 51235; TCP is 51234)
      --config <file>    JSON mapping file, see docs/config.example.json
      --invert-knob      Swap knob rotation direction
      --debug            Print every HID element and every command
      -h, --help         Show this help
    """)
}

func main() -> Int32 {
    var config = BridgeConfig()
    var debug = false
    let args = Array(CommandLine.arguments.dropFirst())

    var i = 0
    while i < args.count {
        switch args[i] {
        case "-h", "--help":
            printHelp()
            return 0
        case "--host":
            if i + 1 < args.count { config.host = args[i + 1]; i += 1 }
        case "--port":
            if i + 1 < args.count, let p = UInt16(args[i + 1]) { config.port = p; i += 1 }
        case "--config":
            if i + 1 < args.count {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: args[i + 1]))
                    config = try JSONDecoder().decode(BridgeConfig.self, from: data)
                } catch {
                    FileHandle.standardError.write(Data("Config error: \(error.localizedDescription)\n".utf8))
                    return 1
                }
                i += 1
            }
        case "--invert-knob":
            config.invertKnob = true
        case "--debug":
            debug = true
        default:
            print("Unknown option: \(args[i])")
            printHelp()
            return 1
        }
        i += 1
    }

    do {
        let sender = try CompanionSender(host: config.host, port: config.port)
        let watcher = DialWatcher(sender: sender, config: config, debug: debug)
        watcher.start()
        print("[bridge] watching for Ulanzi D100H (VID 0xFFF1, PID 0x0082)")
        print("[bridge] forwarding to Companion at \(config.host):\(config.port) (UDP)")
        print("[bridge] Ctrl-C to quit")
        CFRunLoopRun()
    } catch {
        FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        return 1
    }
    return 0
}

exit(main())
