import Foundation

public enum NexoCommand: Codable, Equatable, Sendable {
    case setVolume(Int)
    case volumeStep(Int)
    case toggleMute
    case playPause
    case nextTrack
    case previousTrack
    case lockScreen
    case sleepDisplay
    case sleepMac
    case slideNext
    case slidePrevious
    case brightness(Int)
    case setBrightness(Int)
    case pressKey(String)
    case runShortcut(String)
    case openApp(String)
    case typeText(String)
    case mouseMove(dx: Int, dy: Int)
    case click
    case rightClick
    case doubleClick
    case scroll(Int)
    case toggleKeepAwake
    case toggleDarkMode
    case screenshot
    case findMac
}

public struct MacStatus: Codable, Equatable, Sendable {
    public var hostName: String
    public var battery: Int?
    public var charging: Bool
    public var volume: Int
    public var muted: Bool
    public var sentAt: Date
    public var cpu: Int = 0
    public var memory: Int = 0
    public var nowPlaying: String?
    public var keepAwake: Bool = false
    public var darkMode: Bool = false
    public var accessibility: Bool = true
    public var brightness: Int = 50

    public init(hostName: String, battery: Int?, charging: Bool, volume: Int, muted: Bool, sentAt: Date = Date(),
                cpu: Int = 0, memory: Int = 0, nowPlaying: String? = nil, keepAwake: Bool = false, darkMode: Bool = false, accessibility: Bool = true, brightness: Int = 50) {
        self.accessibility = accessibility
        self.brightness = brightness
        self.cpu = cpu
        self.memory = memory
        self.nowPlaying = nowPlaying
        self.keepAwake = keepAwake
        self.darkMode = darkMode
        self.hostName = hostName
        self.battery = battery
        self.charging = charging
        self.volume = volume
        self.muted = muted
        self.sentAt = sentAt
    }
}

public enum NexoMessage: Codable, Equatable, Sendable {
    case hello(device: String)
    case command(NexoCommand)
    case status(MacStatus)
    case alert(title: String, body: String)
    case clipboard(String)
    case ack(ok: Bool)
    case catalog(shortcuts: [String], apps: [String])
    case requestCatalog
    case requestIcons([String])
    case icons([String: Data])
}

struct Envelope: Codable {
    var seq: UInt64
    var message: NexoMessage
}

public let nexoServiceType = "_nexo._tcp"
