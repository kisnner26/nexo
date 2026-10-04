import Foundation
import NexoCore

// uso: nexoprobe CODIGO [volumen]   — se conecta como lo haría el iPhone y muestra lo que pasa.
@MainActor func run() async {
    let args = CommandLine.arguments
    guard args.count > 1 else { print("uso: nexoprobe CODIGO"); return }
    let client = NexoClient()
    client.configure(code: args[1], deviceName: "sonda")
    client.start()
    var lastState = ""
    let t0 = Date()
    while Date().timeIntervalSince(t0) < 25 {
        let s = "\(client.state)"
        if s != lastState { print(String(format: "%5.1fs estado: %@", Date().timeIntervalSince(t0), s)); lastState = s }
        if client.isConnected, client.ackCount == 0 {
            print("status:", client.status as Any)
            let a = args.count > 2 ? args[2] : "vol:64"
            let v = String(a.dropFirst(a.firstIndex(of: ":").map { a.distance(from: a.startIndex, to: $0) + 1 } ?? 0))
            switch a.split(separator: ":").first.map(String.init) ?? "" {
            case "icon":
                client.loadIcon(for: v)
                for _ in 0..<40 { if client.icons[v] != nil { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
                print("icono \(v):", client.icons[v]?.count ?? 0, "bytes; apps en catálogo:", client.apps.count, "primeras:", client.apps.prefix(5))
                client.send(.pressKey("escape"))
            case "app": client.send(.openApp(v))
            case "bri": client.send(.brightness(Int(v) ?? 1))
            case "move": client.send(.mouseMove(dx: Int(v) ?? 40, dy: 0))
            case "type": client.send(.typeText(v))
            default: client.send(.setVolume(Int(v) ?? 64))
            }
        }
        if client.ackCount > 0 { print("ack recibido: la orden llegó"); print("shortcuts:", client.shortcuts.count, "apps:", client.apps.count); break }
        try? await Task.sleep(nanoseconds: 200_000_000)
    }
    client.stop()
}
await run()
