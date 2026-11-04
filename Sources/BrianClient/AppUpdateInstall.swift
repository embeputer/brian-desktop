import CoreFoundation
import Foundation

/// Where a downloaded Brian.app will be copied, and the staged copy that is safe to install after quit.
public struct PreparedUpdate: Equatable, Sendable {
    public var stagedApp: URL
    public var destination: URL
    public var version: String
    public var build: String
    public var cleanup: URL

    public init(stagedApp: URL, destination: URL, version: String, build: String, cleanup: URL) {
        self.stagedApp = stagedApp
        self.destination = destination
        self.version = version
        self.build = build
        self.cleanup = cleanup
    }
}

public enum AppIdentity {
    public static let bundleIdentifier = "dev.brian.desktop"
    public static let appName = "Brian.app"
    public static let executableName = "BrianDesktop"
}

/// Finds Brian.app inside a mounted disk image or an unzipped archive and copies it aside.
public enum AppUpdateInstaller {
    public static func destination(
        runningBundle: URL?,
        applicationsDirectory: URL,
        userApplicationsDirectory: URL,
        isWritableDirectory: @escaping (URL) -> Bool,
        isSymbolicLink: @escaping (URL) -> Bool
    ) -> URL {
        if let runningBundle, runningBundle.pathExtension == "app", !isSymbolicLink(runningBundle) {
            let parent = runningBundle.deletingLastPathComponent()
            if isWritableDirectory(parent) {
                return runningBundle
            }
        }
        let systemApp = applicationsDirectory.appendingPathComponent(AppIdentity.appName)
        if isWritableDirectory(applicationsDirectory), !isSymbolicLink(systemApp) {
            return systemApp
        }
        return userApplicationsDirectory.appendingPathComponent(AppIdentity.appName)
    }

    public static func stage(
        contentsRoot: URL,
        item: ReleaseFeedItem,
        runningBundle: URL?,
        applicationsDirectory: URL,
        userApplicationsDirectory: URL,
        stagingDirectory: URL,
        fileManager: FileManager = .default,
        isWritableDirectory: ((URL) -> Bool)? = nil,
        isSymbolicLink: ((URL) -> Bool)? = nil,
        copy: ((URL, URL) throws -> Void)? = nil
    ) throws -> PreparedUpdate {
        let app = try locateApp(in: contentsRoot, fileManager: fileManager)
        try ensureInside(root: contentsRoot, candidate: app)
        let info = try readInfo(at: app, fileManager: fileManager)
        guard info.bundleID == AppIdentity.bundleIdentifier else {
            throw BrianClientError(message: "The downloaded app is not Brian.")
        }
        guard info.version == item.version else {
            throw BrianClientError(message: "The downloaded app is a different version than the feed announced.")
        }
        if !item.build.isEmpty, info.build != item.build {
            throw BrianClientError(message: "The downloaded app is a different version than the feed announced.")
        }
        let executable = app
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(info.executable)
        guard fileManager.fileExists(atPath: executable.path) else {
            throw BrianClientError(message: "The update does not contain Brian.app.")
        }

        let writable = isWritableDirectory ?? { fileManager.isWritableFile(atPath: $0.path) }
        let link = isSymbolicLink ?? { symbolicLink($0) }
        let destination = destination(
            runningBundle: runningBundle,
            applicationsDirectory: applicationsDirectory,
            userApplicationsDirectory: userApplicationsDirectory,
            isWritableDirectory: writable,
            isSymbolicLink: link
        )
        if link(destination) {
            throw BrianClientError(message: "Couldn't replace the app because \(destination.path) is a shortcut.")
        }

        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let staged = stagingDirectory.appendingPathComponent(AppIdentity.appName)
        if fileManager.fileExists(atPath: staged.path) {
            try fileManager.removeItem(at: staged)
        }
        if let copy {
            try copy(app, staged)
        } else {
            try fileManager.copyItem(at: app, to: staged)
        }
        return PreparedUpdate(
            stagedApp: staged,
            destination: destination,
            version: item.version,
            build: item.build,
            cleanup: stagingDirectory
        )
    }

    private static func locateApp(in root: URL, fileManager: FileManager) throws -> URL {
        if root.pathExtension == "app" {
            return root
        }
        if let found = search(root: root, fileManager: fileManager, depth: 0) {
            return found
        }
        throw BrianClientError(message: "The update does not contain Brian.app.")
    }

    private static func search(root: URL, fileManager: FileManager, depth: Int) -> URL? {
        if depth > 3 { return nil }
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let apps = children.filter { $0.pathExtension == "app" }
        if let named = apps.first(where: { $0.lastPathComponent == AppIdentity.appName }) {
            return named
        }
        if let any = apps.first {
            return any
        }
        for child in children {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if let found = search(root: child, fileManager: fileManager, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    private static func ensureInside(root: URL, candidate: URL) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let candidatePath = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        if candidatePath == rootPath { return }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard candidatePath.hasPrefix(prefix) else {
            throw BrianClientError(message: "The downloaded app is not inside the update.")
        }
    }

    private static func readInfo(at app: URL, fileManager: FileManager) throws -> (bundleID: String, version: String, build: String, executable: String) {
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        guard let data = fileManager.contents(atPath: plistURL.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = dictionary(plist)
        else {
            throw BrianClientError(message: "The update does not contain Brian.app.")
        }
        let bundleID = text(info["CFBundleIdentifier"])
        let version = text(info["CFBundleShortVersionString"])
        let build = text(info["CFBundleVersion"])
        let executable = text(info["CFBundleExecutable"])
        let resolvedExecutable = executable.isEmpty ? AppIdentity.executableName : executable
        guard !bundleID.isEmpty, !version.isEmpty else {
            throw BrianClientError(message: "The update does not contain Brian.app.")
        }
        return (bundleID, version, build, resolvedExecutable)
    }

    private static func text(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return ""
    }

    private static func symbolicLink(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values?.isSymbolicLink == true
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
}

public struct ExtractedArchive: Equatable, Sendable {
    public var contentsRoot: URL
    public var mountPoint: URL?

    public init(contentsRoot: URL, mountPoint: URL?) {
        self.contentsRoot = contentsRoot
        self.mountPoint = mountPoint
    }
}

/// Mounts a `.dmg` with `hdiutil` or expands a `.zip` with `ditto`. Both ship with macOS.
public enum UpdateArchive {
    public static let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")
    public static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")

    public enum Kind: Equatable, Sendable {
        case dmg
        case zip
    }

    public static func kind(for url: URL) -> Kind? {
        switch url.pathExtension.lowercased() {
        case "dmg":
            return .dmg
        case "zip":
            return .zip
        default:
            return nil
        }
    }

    public static func mountPoint(fromHdiutilPlist data: Data) throws -> URL {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = dictionary(plist),
              let entities = array(root["system-entities"])
        else {
            throw BrianClientError(message: "The disk image did not mount.")
        }
        for entity in entities {
            guard let info = dictionary(entity),
                  let point = info["mount-point"] as? String
            else { continue }
            let trimmed = point.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return URL(fileURLWithPath: trimmed)
            }
        }
        throw BrianClientError(message: "The disk image did not mount.")
    }

    public static func detachArguments(mountPoint: URL) -> [String] {
        ["detach", mountPoint.path]
    }

    public static func extract(
        archive: URL,
        workDirectory: URL,
        runner: CommandRunning,
        fileManager: FileManager = .default
    ) throws -> ExtractedArchive {
        switch kind(for: archive) {
        case .dmg:
            let output = try runner.run(
                executable: hdiutil,
                arguments: ["attach", "-nobrowse", "-readonly", "-plist", archive.path],
                environment: ProcessInfo.processInfo.environment
            )
            guard output.status == 0 else {
                throw BrianClientError(message: "The disk image did not mount. \(tail(output.stderr))")
            }
            let mount = try mountPoint(fromHdiutilPlist: Data(output.stdout.utf8))
            return ExtractedArchive(contentsRoot: mount, mountPoint: mount)
        case .zip:
            let destination = workDirectory.appendingPathComponent("unzipped")
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let output = try runner.run(
                executable: ditto,
                arguments: ["-xk", archive.path, destination.path],
                environment: ProcessInfo.processInfo.environment
            )
            guard output.status == 0 else {
                throw BrianClientError(message: "The update archive could not be opened. \(tail(output.stderr))")
            }
            return ExtractedArchive(contentsRoot: destination, mountPoint: nil)
        case nil:
            throw BrianClientError(message: "The download URL is not an https link to a .dmg or .zip.")
        }
    }

    private static func tail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "The command failed." }
        if trimmed.count <= 500 { return trimmed }
        return String(trimmed.suffix(500))
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
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

    private static func array(_ value: Any?) -> [Any]? {
        guard let value else { return nil }
        if let array = value as? [Any] {
            return array
        }
        if let array = value as? NSArray {
            return array.map { $0 }
        }
        return nil
    }
}

public struct UpdateRelaunchCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

/// A helper that outlives the app: wait until this process exits, replace the bundle, then open it.
public enum UpdateRelaunch {
    public static let script = """
    #!/bin/sh
    set -eu
    pid="$1"
    staged="$2"
    dest="$3"
    cleanup="${4:-}"
    log="${HOME}/Library/Logs/Brian/update.log"
    mkdir -p "$(dirname "$log")"
    /usr/bin/nohup /bin/sh -c '
    set -eu
    pid="$1"
    staged="$2"
    dest="$3"
    cleanup="${4:-}"
    while kill -0 "$pid" 2>/dev/null; do
      /bin/sleep 0.2
    done
    /bin/mkdir -p "$(dirname "$dest")"
    tmp="${dest}.installing"
    /bin/rm -rf "$tmp"
    /usr/bin/ditto "$staged" "$tmp"
    /bin/rm -rf "$dest"
    /bin/mv "$tmp" "$dest"
    /usr/bin/xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true
    if [ -n "$cleanup" ]; then
      /bin/rm -rf "$cleanup"
    fi
    /usr/bin/open "$dest"
    ' _ "$pid" "$staged" "$dest" "$cleanup" >>"$log" 2>&1 &
    exit 0
    """

    public static func command(
        scriptURL: URL,
        pid: Int32,
        stagedApp: URL,
        destination: URL,
        cleanup: URL?
    ) -> UpdateRelaunchCommand {
        var arguments = [scriptURL.path, String(pid), stagedApp.path, destination.path]
        if let cleanup {
            arguments.append(cleanup.path)
        }
        return UpdateRelaunchCommand(executable: URL(fileURLWithPath: "/usr/bin/nohup"), arguments: arguments)
    }
}
