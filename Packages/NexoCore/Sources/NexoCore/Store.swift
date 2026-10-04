import Foundation

/// Preferencias compartidas entre la app y sus extensiones (App Group si existe).
public enum NexoStore {
    public static let groupID = "group.com.kisnner26.nexo"

    static var defaults: UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    public static var code: String? {
        get { defaults.string(forKey: "code") }
        set { defaults.set(newValue, forKey: "code") }
    }

    public static var lastStatus: MacStatus? {
        get { defaults.data(forKey: "status").flatMap { try? JSONDecoder().decode(MacStatus.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "status") }
    }

    public static var catalog: (shortcuts: [String], apps: [String]) {
        get {
            (defaults.stringArray(forKey: "shortcuts") ?? [], defaults.stringArray(forKey: "apps") ?? [])
        }
        set {
            defaults.set(newValue.shortcuts, forKey: "shortcuts")
            defaults.set(newValue.apps, forKey: "apps")
        }
    }
}
