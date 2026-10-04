import AppKit
import SwiftUI

/// Indicador de volumen / brillo. Primero intenta el HUD nativo de macOS (OSDUIHelper);
/// si el sistema no lo muestra, dibuja uno con el mismo aspecto (material HUD, icono y 16 segmentos).
@MainActor
enum OSD {
    enum Kind { case volume(muted: Bool), brightness }

    private static var panel: NSPanel?
    private static var hideTask: DispatchWorkItem?

    static func show(_ kind: Kind, level: Double) {
        let level = min(1, max(0, level))
        showNative(kind, level: level)
        // si OSDUIHelper no despierta, el sistema no lo está pintando: se usa el HUD propio
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.OSDUIHelper").isEmpty {
                showFallback(kind, level: level)
            }
        }
    }

    // MARK: HUD nativo

    @discardableResult
    private static func showNative(_ kind: Kind, level: Double) -> Bool {
        dlopen("/System/Library/PrivateFrameworks/OSD.framework/OSD", RTLD_LAZY)
        guard let cls = NSClassFromString("OSDManager") as? NSObject.Type,
              let mgr = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject
        else { return false }
        let sel = NSSelectorFromString("showImage:onDisplayID:priority:msecUntilFade:filledChiclets:totalChiclets:locked:")
        guard mgr.responds(to: sel) else { return false }
        typealias Show = @convention(c) (AnyObject, Selector, Int64, UInt32, UInt32, UInt32, UInt32, UInt32, Bool) -> Void
        let image: Int64
        switch kind {
        case .brightness: image = 1
        case .volume(let muted): image = muted ? 4 : 3
        }
        let filled: UInt32 = { if case .volume(true) = kind { return 0 }; return UInt32((level * 16).rounded()) }()
        unsafeBitCast(mgr.method(for: sel), to: Show.self)(mgr, sel, image, CGMainDisplayID(), 0x1f, 1500, filled, 16, false)
        // si OSDUIHelper no despierta en un instante, el sistema no lo está pintando
        return NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.OSDUIHelper").isEmpty == false
    }

    // MARK: HUD propio (respaldo)

    private static func showFallback(_ kind: Kind, level: Double) {
        let size = NSSize(width: 200, height: 200)
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .screenSaver
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel = p
            return p
        }()
        p.contentView = NSHostingView(rootView: HUDView(kind: kind, level: level))
        if let s = NSScreen.main {
            p.setFrameOrigin(NSPoint(x: s.frame.midX - size.width / 2, y: s.frame.minY + 140))
        }
        p.alphaValue = 1
        p.orderFrontRegardless()
        hideTask?.cancel()
        let t = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.35; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
        hideTask = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: t)
    }
}

private struct HUDView: View {
    let kind: OSD.Kind
    let level: Double

    private var symbol: String {
        switch kind {
        case .brightness: "sun.max.fill"
        case .volume(let muted): muted ? "speaker.slash.fill" : (level > 0.5 ? "speaker.wave.3.fill" : level > 0 ? "speaker.wave.1.fill" : "speaker.fill")
        }
    }

    private var filled: Int { if case .volume(true) = kind { return 0 }; return Int((level * 16).rounded()) }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            Image(systemName: symbol).font(.system(size: 78, weight: .regular)).foregroundStyle(.white.opacity(0.92))
            HStack(spacing: 2) {
                ForEach(0..<16, id: \.self) { i in
                    Rectangle().fill(i < filled ? Color.white.opacity(0.95) : Color.white.opacity(0.28)).frame(width: 7, height: 8)
                }
            }
            .padding(.bottom, 22)
        }
        .frame(width: 200, height: 200)
        .background(VisualEffect())
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
