import Foundation

/// How the app reaches Brian, saved after the first-launch choice.
public struct ConnectionSettings: Equatable, Codable, Sendable {
    public enum Mode: String, Codable, Sendable {
        case local
        case remote
    }

    public var mode: Mode
    /// Absolute path used for a local RPC process. Empty means "look up brian, and install it if needed."
    public var executablePath: String
    /// Normalized `brian serve` origin, such as `https://host:7333` or `http://localhost:7333`.
    public var remoteAddress: String
    /// Bearer token from that machine's `~/.brian/agent/serve.json`.
    public var remoteToken: String

    public static let storageKey = "dev.brian.desktop.connection"
    public static let legacyExecutableKey = "dev.brian.desktop.executable"

    public init(mode: Mode, executablePath: String, remoteAddress: String, remoteToken: String) {
        self.mode = mode
        self.executablePath = executablePath
        self.remoteAddress = remoteAddress
        self.remoteToken = remoteToken
    }
}

public struct ConnectionSettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ConnectionSettings? {
        if let data = defaults.data(forKey: ConnectionSettings.storageKey) {
            if let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
                return settings
            }
            return nil
        }
        if let legacy = defaults.string(forKey: ConnectionSettings.legacyExecutableKey), !legacy.isEmpty {
            return ConnectionSettings(
                mode: .local,
                executablePath: legacy,
                remoteAddress: "",
                remoteToken: ""
            )
        }
        return nil
    }

    public func save(_ settings: ConnectionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: ConnectionSettings.storageKey)
    }

    public func hasSeenWelcome() -> Bool {
        defaults.bool(forKey: FirstLaunch.welcomeSeenKey)
    }

    public func markWelcomeSeen() {
        defaults.set(true, forKey: FirstLaunch.welcomeSeenKey)
    }
}

/// What the first launch shows. Welcome is recorded on its own, before a connection is chosen.
public enum FirstLaunchStep: Equatable, Sendable {
    case welcome
    case setup
    case ready
}

public enum FirstLaunch {
    public static let welcomeSeenKey = "dev.brian.desktop.welcome.seen"

    public static func step(welcomeSeen: Bool, hasSavedConnection: Bool, choosingConnection: Bool) -> FirstLaunchStep {
        if choosingConnection {
            return .setup
        }
        if hasSavedConnection {
            return .ready
        }
        if welcomeSeen {
            return .setup
        }
        return .welcome
    }
}
