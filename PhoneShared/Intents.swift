import AppIntents
import NexoCore

struct PlayPauseMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Reproducir o pausar en la Mac"
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.playPause)
        return .result()
    }
}

struct NextTrackMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Siguiente canción en la Mac"
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.nextTrack)
        return .result()
    }
}

struct LockMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Bloquear la Mac"
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.lockScreen)
        return .result()
    }
}

struct ToggleMuteMacIntent: AppIntent {
    static var title: LocalizedStringResource = "Silenciar o activar sonido de la Mac"
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.toggleMute)
        return .result()
    }
}

struct SetMacVolumeIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajustar volumen de la Mac"
    @Parameter(title: "Volumen", default: 40, inclusiveRange: (0, 100)) var level: Int
    func perform() async throws -> some IntentResult {
        _ = await NexoOneShot.run(.setVolume(level))
        return .result()
    }
}

struct NexoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayPauseMacIntent(), phrases: ["Pausar música en la Mac con \(.applicationName)"],
                    shortTitle: "Play/Pausa", systemImageName: "playpause.fill")
        AppShortcut(intent: LockMacIntent(), phrases: ["Bloquear la Mac con \(.applicationName)"],
                    shortTitle: "Bloquear Mac", systemImageName: "lock.fill")
        AppShortcut(intent: ToggleMuteMacIntent(), phrases: ["Silenciar la Mac con \(.applicationName)"],
                    shortTitle: "Silenciar", systemImageName: "speaker.slash.fill")
    }
}
