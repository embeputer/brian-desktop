#if os(macOS)
import AppKit
import BrianClient
import Combine
import Foundation

@MainActor
final class UpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case available(ReleaseFeedItem)
        case downloading(ReleaseFeedItem, fraction: Double)
        case ready(ReleaseFeedItem)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var showsPrompt = false
    @Published var showsUpToDate = false

    let currentVersion: AppVersion
    private var didLaunchCheck = false
    private var downloadTask: Task<Void, Never>?
    private var prepared: PreparedUpdate?
    private let downloader = UpdateDownloader()

    init(currentVersion: AppVersion? = nil) {
        self.currentVersion = currentVersion ?? AppVersion.current(info: Bundle.main.infoDictionary)
    }

    var menuEnabled: Bool {
        switch phase {
        case .checking, .downloading:
            return false
        case .idle, .available, .ready, .failed:
            return true
        }
    }

    func checkOnLaunch() {
        guard !didLaunchCheck else { return }
        didLaunchCheck = true
        phase = .checking
        Task { await runCheck(manual: false) }
    }

    func checkManually() {
        switch phase {
        case .available, .ready, .failed:
            showsPrompt = true
        case .checking, .downloading:
            break
        case .idle:
            phase = .checking
            Task { await runCheck(manual: true) }
        }
    }

    func later() {
        showsPrompt = false
    }

    func install() {
        guard case .available(let item) = phase else { return }
        downloadTask?.cancel()
        downloadTask = Task { await downloadAndStage(item) }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloader.cancel()
    }

    func installAndRelaunch() {
        guard let prepared else { return }
        do {
            try UpdateLauncher.start(prepared: prepared)
            NSApplication.shared.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
            showsPrompt = true
        }
    }

    func dismissFailure() {
        showsPrompt = false
        phase = .idle
    }

    private func runCheck(manual: Bool) async {
        phase = .checking
        showsUpToDate = false
        do {
            let url = ReleaseFeed.resolvedURL(
                infoFeed: Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                environment: ProcessInfo.processInfo.environment
            )
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            request.setValue("BrianDesktop", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            try ReleaseFeed.validateHTTP(statusCode: http?.statusCode ?? -1, finalURL: response.url)
            let decision = try ReleaseFeed.decide(
                data: data,
                currentVersion: currentVersion.version,
                currentBuild: currentVersion.build,
                systemVersion: Self.systemVersion()
            )
            switch decision {
            case .available(let item):
                phase = .available(item)
                showsPrompt = true
            case .upToDate:
                phase = .idle
                showsUpToDate = manual
            case .requiresNewerSystem(let version, let minimum):
                if manual {
                    phase = .failed(UpdatePromptCopy.requiresNewerSystem(version: version, minimum: minimum))
                    showsPrompt = true
                } else {
                    phase = .idle
                }
            }
        } catch {
            if manual {
                phase = .failed(error.localizedDescription)
                showsPrompt = true
            } else {
                phase = .idle
            }
        }
    }

    private func downloadAndStage(_ item: ReleaseFeedItem) async {
        phase = .downloading(item, fraction: 0)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("dev.brian.desktop-update-\(UUID().uuidString)", isDirectory: true)
        let ext = item.downloadURL.pathExtension.isEmpty ? "dmg" : item.downloadURL.pathExtension
        let archive = work.appendingPathComponent("Brian.\(ext)")
        let runningBundle = Bundle.main.bundleURL
        do {
            try await downloader.download(from: item.downloadURL, to: archive) { [weak self] fraction in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.phase {
                        self.phase = .downloading(item, fraction: fraction)
                    }
                }
            }
            try Task.checkCancellation()
            let staged = try await Task.detached(priority: .userInitiated) {
                try Self.prepare(archive: archive, item: item, work: work, runningBundle: runningBundle)
            }.value
            guard stillDownloading(item) else { return }
            var installed = staged
            installed.cleanup = work
            prepared = installed
            phase = .ready(item)
        } catch is CancellationError {
            if stillDownloading(item) {
                phase = .available(item)
            }
        } catch let error as URLError where error.code == .cancelled {
            if stillDownloading(item) {
                phase = .available(item)
            }
        } catch {
            guard stillDownloading(item) else { return }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            showsPrompt = true
        }
    }

    private func stillDownloading(_ item: ReleaseFeedItem) -> Bool {
        if case .downloading(let current, _) = phase {
            return current == item
        }
        return false
    }

    private static func prepare(archive: URL, item: ReleaseFeedItem, work: URL, runningBundle: URL) throws -> PreparedUpdate {
        let runner = ProcessCommandRunner()
        let extracted = try UpdateArchive.extract(
            archive: archive,
            workDirectory: work,
            runner: runner,
            fileManager: .default
        )
        defer {
            if let mount = extracted.mountPoint {
                _ = try? runner.run(
                    executable: UpdateArchive.hdiutil,
                    arguments: UpdateArchive.detachArguments(mountPoint: mount),
                    environment: ProcessInfo.processInfo.environment
                )
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return try AppUpdateInstaller.stage(
            contentsRoot: extracted.contentsRoot,
            item: item,
            runningBundle: runningBundle,
            applicationsDirectory: URL(fileURLWithPath: "/Applications"),
            userApplicationsDirectory: home.appendingPathComponent("Applications"),
            stagingDirectory: work.appendingPathComponent("staged"),
            fileManager: .default,
            copy: { source, destination in
                let result = try runner.run(
                    executable: UpdateArchive.ditto,
                    arguments: [source.path, destination.path],
                    environment: ProcessInfo.processInfo.environment
                )
                guard result.status == 0 else {
                    let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    throw BrianClientError(message: detail.isEmpty ? "Couldn't copy the update." : "Couldn't copy the update. \(detail)")
                }
            }
        )
    }

    private static func systemVersion() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

enum UpdateLauncher {
    static func start(prepared: PreparedUpdate) throws {
        let scriptURL = prepared.cleanup.appendingPathComponent("install.sh")
        try UpdateRelaunch.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let command = UpdateRelaunch.command(
            scriptURL: scriptURL,
            pid: ProcessInfo.processInfo.processIdentifier,
            stagedApp: prepared.stagedApp,
            destination: prepared.destination,
            cleanup: prepared.cleanup
        )
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
#endif
