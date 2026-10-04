import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NexoCore

/// Todo lo que NO es de pantalla corre fuera del hilo principal.
enum MacActions {
    static let queue = DispatchQueue(label: "nexo.actions")

    // MARK: Órdenes

    static func run(_ c: NexoCommand) {
        switch c {
        case .setVolume(let v): setVolume(v); showVolumeHUD()
        case .volumeStep(let d): setVolume(volume().level + d); showVolumeHUD()
        case .toggleMute:
            osa("set volume output muted (not (output muted of (get volume settings)))")
            showVolumeHUD()
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        case .lockScreen: lock()
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])
        case .sleepMac: shell("/usr/bin/pmset", ["sleepnow"])
        case .slideNext: key(kVK_RightArrow)
        case .slidePrevious: key(kVK_LeftArrow)
        case .brightness(let d): changeBrightness(Double(d) / 16)
        case .setBrightness(let v): setBrightness(Double(v) / 100)
        case .pressKey(let k): pressNamedKey(k)
        case .runShortcut(let name): shell("/usr/bin/shortcuts", ["run", name])
        case .openApp(let name): shell("/usr/bin/open", ["-a", name])
        case .mouseMove(let dx, let dy): moveMouse(dx, dy)
        case .click: click(.left, count: 1)
        case .doubleClick: click(.left, count: 2)
        case .rightClick: click(.right, count: 1)
        case .scroll(let dy): scroll(dy)
        case .toggleDarkMode:
            osa("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .screenshot: shell("/usr/sbin/screencapture", ["-c"])
        case .findMac:
            setVolume(85)
            for _ in 0..<3 { shell("/usr/bin/afplay", ["/System/Library/Sounds/Sosumi.aiff"]) }
        case .typeText, .toggleKeepAwake: break   // los resuelve el hub (necesitan su estado)
        }
    }

    // MARK: Lectura de estado

    static func volume() -> (level: Int, muted: Bool) {
        let out = osa("set v to get volume settings\nreturn ((output volume of v) as text) & \",\" & ((output muted of v) as text)")
        let parts = out.split(separator: ",").map(String.init)
        return (Int(parts.first ?? "") ?? 0, parts.last == "true")
    }

    static func setVolume(_ v: Int) {
        osa("set volume output volume \(min(100, max(0, v))) without output muted")
    }

    static func nowPlaying() -> String? {
        for app in ["Music", "Spotify"] {
            guard NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName == app }) else { continue }
            let out = osa("""
            tell application "\(app)"
              if player state is playing or player state is paused then
                return (name of current track) & "\u{1F}" & (artist of current track)
              end if
            end tell
            """)
            let p = out.components(separatedBy: "\u{1F}")
            if p.count == 2, !p[0].isEmpty { return p[1].isEmpty ? p[0] : "\(p[0]) — \(p[1])" }
        }
        return nil
    }

    static func darkMode() -> Bool {
        shellOutput("/usr/bin/defaults", ["read", "-g", "AppleInterfaceStyle"]).trimmingCharacters(in: .whitespacesAndNewlines) == "Dark"
    }

    nonisolated(unsafe) private static var appPaths: [String: String] = [:]

    /// Apps abiertas primero, luego el resto por orden alfabético.
    static func installedApps() -> [String] {
        var paths: [String: String] = ["Finder": "/System/Library/CoreServices/Finder.app"]
        for dir in ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities"] {
            for f in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".app") {
                paths[String(f.dropLast(4))] = dir + "/" + f
            }
        }
        appPaths = paths
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }.compactMap(\.localizedName).filter { paths[$0] != nil }
        let runningSet = Set(running)
        let rest = paths.keys.filter { !runningSet.contains($0) }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return running.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } + rest
    }

    static func iconPNG(for name: String, side: Int = 96) -> Data? {
        guard let path = appPaths[name] else { return nil }
        let img = NSWorkspace.shared.icon(forFile: path)
        // bitmap de tamaño fijo en píxeles (sin escala retina) para que cada icono pese pocos KB
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Brillo (DisplayServices; las teclas simuladas no cambian el brillo en Apple silicon)

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    static func brightness() -> Double? {
        guard let h = displayServices, let g = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        var f: Float = 0
        return unsafeBitCast(g, to: GetBrightness.self)(CGMainDisplayID(), &f) == 0 ? Double(f) : nil
    }

    static func setBrightness(_ value: Double) {
        guard let h = displayServices, let s = dlsym(h, "DisplayServicesSetBrightness") else { return }
        let target = Float(min(1, max(0.02, value)))
        _ = unsafeBitCast(s, to: SetBrightness.self)(CGMainDisplayID(), target)
        DispatchQueue.main.async { OSD.show(.brightness, level: Double(target)) }
    }

    static func changeBrightness(_ delta: Double) {
        guard let h = displayServices, let s = dlsym(h, "DisplayServicesSetBrightness"), let cur = brightness() else { return }
        let target = Float(min(1, max(0, cur + delta)))
        _ = unsafeBitCast(s, to: SetBrightness.self)(CGMainDisplayID(), target)
        DispatchQueue.main.async { OSD.show(.brightness, level: Double(target)) }
    }

    /// Muestra el indicador de volumen tras un cambio (lee el valor real ya aplicado).
    static func showVolumeHUD() {
        let v = volume()
        DispatchQueue.main.async { OSD.show(.volume(muted: v.muted), level: Double(v.level) / 100) }
    }

    // MARK: Teclado y ratón

    private static func mediaKey(_ key: Int) {
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xa00 : 0xb00)
            let data1 = (key << 16) | ((down ? 0xa : 0xb) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags,
                               timestamp: 0, windowNumber: 0, context: nil,
                               subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func key(_ code: Int, flags: CGEventFlags = []) {
        guard AXIsProcessTrusted() else { return }
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }

    private static func pressNamedKey(_ name: String) {
        let map: [String: Int] = ["return": kVK_Return, "delete": kVK_Delete, "escape": kVK_Escape, "tab": kVK_Tab, "space": kVK_Space,
                                  "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow]
        if let code = map[name] { key(code) }
    }

    static func pasteShortcut() { key(kVK_ANSI_V, flags: .maskCommand) }

    private static func pointer() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private static func moveMouse(_ dx: Int, _ dy: Int) {
        guard AXIsProcessTrusted() else { return }
        func accel(_ d: Int) -> CGFloat { CGFloat(d) * (1.4 + min(abs(CGFloat(d)), 60) / 40) }
        var p = pointer()
        p.x += accel(dx); p.y += accel(dy)
        let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let h = NSScreen.screens.first?.frame.height ?? bounds.height
        p.x = min(max(p.x, bounds.minX), bounds.maxX - 1)
        p.y = min(max(p.y, 0), h - 1)
        CGWarpMouseCursorPosition(p)
        let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)
        e?.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        e?.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        e?.post(tap: .cghidEventTap)
    }

    private static var lastClick = Date.distantPast
    private static var lastClickCount = 0

    private static func click(_ button: CGMouseButton, count: Int) {
        guard AXIsProcessTrusted() else { return }
        let p = pointer()
        // dos toques seguidos cuentan como doble clic para macOS
        let now = Date()
        let base = (button == .left && now.timeIntervalSince(lastClick) < 0.4) ? lastClickCount : 0
        lastClick = now
        lastClickCount = base + count
        let start = base + 1
        let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let up: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        for i in start...(base + count) {
            for type in [down, up] {
                let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button)
                e?.setIntegerValueField(.mouseEventClickState, value: Int64(i))
                e?.post(tap: .cghidEventTap)
            }
        }
    }

    private static func scroll(_ dy: Int) {
        guard AXIsProcessTrusted() else { return }
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(dy * 3), wheel2: 0, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    private static func lock() {
        typealias Lock = @convention(c) () -> Int32
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let s = dlsym(h, "SACLockScreenImmediate") {
            _ = unsafeBitCast(s, to: Lock.self)()
        } else {
            shell("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }

    // MARK: Procesos

    @discardableResult
    static func osa(_ source: String) -> String {
        shellOutput("/usr/bin/osascript", ["-e", source])
    }

    static func shell(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    static func shellOutput(_ path: String, _ args: [String]) -> String {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        // un permiso de Automatización sin contestar no debe colgar el hub
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
