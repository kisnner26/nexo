import AppIntents
import NexoCore
import SwiftUI
import WidgetKit

@main
struct NexoWidgetBundle: WidgetBundle {
    var body: some Widget {
        MacStatusWidget()
        PlayPauseControl()
        NextTrackControl()
        LockControl()
        MuteControl()
    }
}

// MARK: Controles del Centro de control

struct PlayPauseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nexo.playpause") {
            ControlWidgetButton(action: PlayPauseMacIntent()) {
                Label("Play/Pausa Mac", systemImage: "playpause.fill")
            }
        }
        .displayName("Play/Pausa en la Mac")
    }
}

struct NextTrackControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nexo.next") {
            ControlWidgetButton(action: NextTrackMacIntent()) {
                Label("Siguiente en Mac", systemImage: "forward.fill")
            }
        }
        .displayName("Siguiente canción en la Mac")
    }
}

struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nexo.lock") {
            ControlWidgetButton(action: LockMacIntent()) {
                Label("Bloquear Mac", systemImage: "lock.fill")
            }
        }
        .displayName("Bloquear la Mac")
    }
}

struct MuteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "nexo.mute") {
            ControlWidgetButton(action: ToggleMuteMacIntent()) {
                Label("Silenciar Mac", systemImage: "speaker.slash.fill")
            }
        }
        .displayName("Silenciar la Mac")
    }
}

// MARK: Widget de estado

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: MacStatus?
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, status: MacStatus(hostName: "Mac", battery: 80, charging: false, volume: 40, muted: false))
    }
    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: .now, status: NexoStore.lastStatus))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let e = StatusEntry(date: .now, status: NexoStore.lastStatus)
        completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(900))))
    }
}

struct MacStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "nexo.status", provider: StatusProvider()) { entry in
            StatusView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Estado de la Mac")
        .description("Batería y volumen de tu Mac.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

struct StatusView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.status {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(s.battery ?? 0), in: 0...100) { Image(systemName: "laptopcomputer") }
                    currentValueLabel: { Text("\(s.battery ?? 0)") }
                    .gaugeStyle(.accessoryCircular)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Label(s.hostName, systemImage: "laptopcomputer").font(.caption).lineLimit(1)
                    Text(s.battery.map { "\($0)%" } ?? "AC").font(.title.bold())
                    Text(s.charging ? "Cargando" : "Batería").font(.caption2).foregroundStyle(.secondary)
                    Text(s.muted ? "Silenciada" : "Volumen \(s.volume)").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Label("Abre Nexo", systemImage: "link")
        }
    }
}
