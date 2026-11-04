import Foundation

/// One installable release advertised by the Brian appcast.
public struct ReleaseFeedItem: Equatable, Sendable {
    public var version: String
    public var build: String
    public var minimumSystemVersion: String?
    public var downloadURL: URL
    public var releaseNotes: String
    public var length: Int?
    /// Lowercase hex SHA-256 of the archive at `downloadURL`.
    public var sha256: String
    /// Base64 Ed25519 signature of `UpdateSigning.message(version:build:sha256:)`.
    public var signature: String

    public init(
        version: String,
        build: String,
        minimumSystemVersion: String?,
        downloadURL: URL,
        releaseNotes: String,
        length: Int?,
        sha256: String = "",
        signature: String = ""
    ) {
        self.version = version
        self.build = build
        self.minimumSystemVersion = minimumSystemVersion
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
        self.length = length
        self.sha256 = sha256
        self.signature = signature
    }
}

/// What a launch check should do with the feed.
public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    case available(ReleaseFeedItem)
    /// A newer release exists, and this Mac is older than its `minimumSystemVersion`.
    case requiresNewerSystem(version: String, minimumSystemVersion: String)
}

/// The version baked into `Scripts/Info.plist`. A `swift run` binary has no bundle plist, so the check uses this pair.
public struct AppVersion: Equatable, Sendable {
    public var version: String
    public var build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    public static let packaged = AppVersion(version: "0.1.0", build: "1")

    public static func current(info: [String: Any]?) -> AppVersion {
        let version = trimmed(info?["CFBundleShortVersionString"] as? String)
        let build = trimmed(info?["CFBundleVersion"] as? String)
        return AppVersion(
            version: version.isEmpty ? packaged.version : version,
            build: build.isEmpty ? packaged.build : build
        )
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

/// JSON appcast at `releases/latest/download/appcast.json`.
public enum ReleaseFeed {
    public static let defaultURL = URL(string: "https://github.com/embeputer/brian-desktop/releases/latest/download/appcast.json")!
    /// Every installable archive is a release asset of this repo.
    public static let downloadHost = "github.com"
    public static let downloadPathPrefix = "/embeputer/brian-desktop/releases/download/"

    public static func resolvedURL(infoFeed: String?, environment: [String: String]) -> URL {
        if let override = environment["BRIAN_UPDATE_FEED"], let url = httpsURL(override) {
            return url
        }
        if let infoFeed, let url = httpsURL(infoFeed) {
            return url
        }
        return defaultURL
    }

    public static func validateHTTP(statusCode: Int, finalURL: URL?) throws {
        guard (200...299).contains(statusCode) else {
            throw BrianClientError(message: "The release feed returned HTTP \(statusCode).")
        }
        guard finalURL?.scheme?.lowercased() == "https" else {
            throw BrianClientError(message: "The release feed left https.")
        }
    }

    public static func decide(
        data: Data,
        currentVersion: String,
        currentBuild: String,
        systemVersion: String,
        publicKey: String = UpdateSigning.publicKey
    ) throws -> UpdateDecision {
        let items = try parse(data)
        let newer = items.filter {
            isNewer($0, thanVersion: currentVersion, build: currentBuild) &&
                downloadIsAcceptable($0) &&
                UpdateSigning.isSigned($0, publicKey: publicKey)
        }
        let installable = newer.filter { item in
            guard let minimum = item.minimumSystemVersion, !minimum.isEmpty else { return true }
            return compareVersions(systemVersion, minimum) != .orderedAscending
        }
        if let best = installable.max(by: isOrderedBefore) {
            return .available(best)
        }
        if let blocked = newer.max(by: isOrderedBefore), let minimum = blocked.minimumSystemVersion {
            return .requiresNewerSystem(version: blocked.version, minimumSystemVersion: minimum)
        }
        return .upToDate
    }

    static func downloadIsAcceptable(_ item: ReleaseFeedItem) -> Bool {
        guard downloadURLIsAllowed(item.downloadURL) else { return false }
        guard UpdateSigning.isSHA256(item.sha256) else { return false }
        if let length = item.length, length > UpdateDownload.maximumBytes {
            return false
        }
        return true
    }

    /// An https `.dmg` or `.zip` asset under `https://github.com/embeputer/brian-desktop/releases/download/`.
    public static func downloadURLIsAllowed(_ url: URL) -> Bool {
        guard isPlainHTTPS(url), url.host?.lowercased() == downloadHost else { return false }
        guard url.query == nil, url.fragment == nil else { return false }
        let path = url.path
        guard path.hasPrefix(downloadPathPrefix), !path.contains("/../"), !path.contains("/./") else { return false }
        return UpdateArchive.kind(for: url) != nil
    }

    /// GitHub answers a release download with a redirect to its asset CDN.
    public static func downloadRedirectIsAllowed(_ url: URL) -> Bool {
        guard isPlainHTTPS(url), let host = url.host?.lowercased() else { return false }
        return host == downloadHost || host.hasSuffix(".githubusercontent.com")
    }

    private static func isPlainHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil && url.port == nil
    }

    private static func parse(_ data: Data) throws -> [ReleaseFeedItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw BrianClientError(message: "The release feed could not be read.")
        }
        let objects = try feedObjects(json)
        if objects.isEmpty {
            return []
        }
        let items = objects.compactMap(item(from:))
        if items.isEmpty {
            throw BrianClientError(message: "The release feed could not be read.")
        }
        return items
    }

    private static func feedObjects(_ json: Any) throws -> [[String: Any]] {
        if let array = array(json) {
            return array.compactMap(dictionary)
        }
        guard let object = dictionary(json) else {
            throw BrianClientError(message: "The release feed could not be read.")
        }
        if let items = object["items"] {
            guard let array = array(items) else {
                throw BrianClientError(message: "The release feed could not be read.")
            }
            return array.compactMap(dictionary)
        }
        if object["version"] != nil || object["downloadURL"] != nil {
            return [object]
        }
        throw BrianClientError(message: "The release feed could not be read.")
    }

    private static func item(from object: [String: Any]) -> ReleaseFeedItem? {
        guard let version = JSONLookup.string(object["version"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty,
              let urlString = JSONLookup.string(object["downloadURL"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              let downloadURL = URL(string: urlString)
        else { return nil }
        let build: String
        if let text = JSONLookup.string(object["build"])?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            build = text
        } else if let number = JSONLookup.int(object["build"]) {
            build = String(number)
        } else {
            build = ""
        }
        let minimum = JSONLookup.string(object["minimumSystemVersion"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = JSONLookup.string(object["releaseNotes"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReleaseFeedItem(
            version: version,
            build: build,
            minimumSystemVersion: minimum?.isEmpty == false ? minimum : nil,
            downloadURL: downloadURL,
            releaseNotes: notes,
            length: JSONLookup.int(object["length"]),
            sha256: JSONLookup.string(object["sha256"])?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
            signature: JSONLookup.string(object["signature"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    private static func isNewer(_ item: ReleaseFeedItem, thanVersion version: String, build: String) -> Bool {
        switch compareVersions(item.version, version) {
        case .orderedDescending:
            return true
        case .orderedAscending:
            return false
        case .orderedSame:
            return buildNumber(item.build) > buildNumber(build)
        }
    }

    private static func isOrderedBefore(_ lhs: ReleaseFeedItem, _ rhs: ReleaseFeedItem) -> Bool {
        switch compareVersions(lhs.version, rhs.version) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            return buildNumber(lhs.build) < buildNumber(rhs.build)
        }
    }

    private static func buildNumber(_ build: String) -> Int {
        Int(build.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        let head = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? version
        return head.split(separator: ".").map { part in
            Int(part) ?? 0
        }
    }

    private static func httpsURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func dictionary(_ value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for key in dictionary.allKeys {
            guard let stringKey = key as? String else { continue }
            result[stringKey] = dictionary[stringKey]
        }
        return result
    }

    private static func array(_ value: Any) -> [Any]? {
        if let array = value as? [Any] {
            return array
        }
        if let array = value as? NSArray {
            return array.map { $0 }
        }
        return nil
    }
}

public enum UpdateDownload {
    public static let maximumBytes = 250_000_000

    public static func fraction(received: Int64, expected: Int64?) -> Double {
        guard let expected, expected > 0, received > 0 else { return 0 }
        return min(1, Double(received) / Double(expected))
    }
}

/// Strings the update sheet shows. The Mac UI uses these so the prompt stays the same as the tests.
public enum UpdatePromptCopy {
    public static let availableTitle = "A new version of Brian is available"
    public static let installButton = "Install Update"
    public static let laterButton = "Later"
    public static let releaseNotesHeading = "Release notes"
    public static let readyMessage = "Brian will quit, replace this copy, and reopen."
    public static let relaunchButton = "Install and Relaunch"
    public static let cancelButton = "Cancel"
    public static let closeButton = "Close"
    public static let upToDateTitle = "Brian is up to date"
    public static let checkForUpdatesMenu = "Check for Updates…"

    public static func availableMessage(offeredVersion: String, currentVersion: String) -> String {
        "Brian \(offeredVersion) is now available — you have \(currentVersion). Would you like to download it now?"
    }

    public static func downloadingTitle(version: String) -> String {
        "Downloading Brian \(version)"
    }

    public static func readyTitle(version: String) -> String {
        "Brian \(version) is ready to install"
    }

    public static func upToDateMessage(version: String) -> String {
        "You're running Brian \(version)."
    }

    public static func requiresNewerSystem(version: String, minimum: String) -> String {
        "Brian \(version) requires macOS \(minimum) or later."
    }
}
