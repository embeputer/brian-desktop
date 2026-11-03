#if os(macOS)
import BrianClient
import Foundation

@MainActor
final class DesktopModel: ObservableObject {
    @Published private(set) var snapshot: SessionSnapshot = .disconnected
    @Published private(set) var settings: ConnectionSettings?
    @Published private(set) var isBusy = false
    @Published var isChoosingConnection = false
    @Published var setupError: String?
    @Published var prompt = ""
    @Published var executablePath = ""
    @Published var remoteAddress = ""
    @Published var remoteToken = ""

    private let store: ConnectionSettingsStore
    private let workingDirectory: URL
    private var rpc: BrianSession?
    private var serve: ServeSession?

    init(store: ConnectionSettingsStore = ConnectionSettingsStore()) {
        self.store = store
        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
        if let saved = store.load() {
            settings = saved
            executablePath = saved.executablePath
            remoteAddress = saved.remoteAddress
            remoteToken = saved.remoteToken
        }
    }

    var workingDirectoryPath: String { workingDirectory.path }

    var showsSetup: Bool {
        settings == nil || isChoosingConnection
    }

    var canCancelSetup: Bool {
        settings != nil && isChoosingConnection
    }

    func connectIfNeeded() {
        guard rpc == nil, serve == nil, !showsSetup, !isBusy else { return }
        guard let settings else { return }
        switch settings.mode {
        case .local:
            startLocal()
        case .remote:
            startRemote()
        }
    }

    func startLocal() {
        guard !isBusy else { return }
        let fromSetup = showsSetup
        isBusy = true
        setupError = nil
        let typed = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = ConnectionSettings(
            mode: .local,
            executablePath: typed,
            remoteAddress: remoteAddress,
            remoteToken: remoteToken
        )
        store.save(saved)
        settings = saved
        if fromSetup {
            isChoosingConnection = true
        }
        snapshot.phase = .launching
        snapshot.statusLine = "Looking for brian…"
        let environment = ProcessInfo.processInfo.environment
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result(catching: { try Self.locateLocalBrian(explicitPath: typed, environment: environment) })
            DispatchQueue.main.async {
                self?.finishLocal(result, returnToSetup: fromSetup)
            }
        }
    }

    func startRemote() {
        guard !isBusy else { return }
        switch ServeAddress.parse(address: remoteAddress, token: remoteToken) {
        case .failure(let error):
            setupError = error.message
        case .success(let endpoint):
            setupError = nil
            isChoosingConnection = false
            let saved = ConnectionSettings(
                mode: .remote,
                executablePath: executablePath,
                remoteAddress: endpoint.baseURL.absoluteString,
                remoteToken: endpoint.token
            )
            store.save(saved)
            settings = saved
            remoteAddress = saved.remoteAddress
            openServe(endpoint)
        }
    }

    func cancelSetup() {
        guard canCancelSetup else { return }
        isChoosingConnection = false
        setupError = nil
        connectIfNeeded()
    }

    func changeConnection() {
        guard !isBusy else { return }
        stopSessions()
        setupError = nil
        isChoosingConnection = true
    }

    func reconnect() {
        guard let settings, !isBusy else { return }
        switch settings.mode {
        case .local:
            startLocal()
        case .remote:
            startRemote()
        }
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let rpc {
            do {
                try rpc.sendPrompt(text)
                prompt = ""
            } catch {
                snapshot.statusLine = error.localizedDescription
            }
            return
        }
        if let serve {
            serve.sendPrompt(text)
            prompt = ""
        }
    }

    func abort() {
        try? rpc?.abort()
        serve?.cancelPrompt()
    }

    func stop() {
        rpc?.stop()
        serve?.stop()
    }

    private static func locateLocalBrian(explicitPath: String, environment: [String: String]) throws -> URL {
        if !explicitPath.isEmpty {
            guard let existing = BrianExecutableResolver.resolve(explicitPath: explicitPath, environment: environment) else {
                throw BrianClientError(message: "Couldn't find \(explicitPath).")
            }
            return existing
        }
        return try LocalBrianSetup.resolveOrInstall(explicitPath: nil, environment: environment, runner: ProcessCommandRunner())
    }

    private func finishLocal(_ result: Result<URL, Error>, returnToSetup: Bool) {
        isBusy = false
        switch result {
        case .failure(let error):
            let message = error.localizedDescription
            setupError = message
            snapshot = SessionSnapshot(
                phase: .failed(message),
                messages: snapshot.messages,
                statusLine: message,
                stderr: snapshot.stderr,
                modelLabel: snapshot.modelLabel,
                sessionID: snapshot.sessionID
            )
            if returnToSetup {
                isChoosingConnection = true
            }
        case .success(let url):
            executablePath = url.path
            if var saved = settings {
                saved.executablePath = url.path
                saved.mode = .local
                store.save(saved)
                settings = saved
            }
            isChoosingConnection = false
            openRPC(executable: url)
        }
    }

    private func openRPC(executable: URL) {
        stopSessions()
        let configuration = BrianLaunchConfiguration.fromEnvironment(
            executableURL: executable,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: workingDirectory
        )
        let session = BrianSession(configuration: configuration)
        session.onChange = { [weak self] snapshot in
            self?.publish(snapshot)
        }
        rpc = session
        do {
            try session.start()
        } catch {
            publish(session.snapshot)
        }
    }

    private func openServe(_ endpoint: ServeEndpoint) {
        stopSessions()
        let session = ServeSession(endpoint: endpoint)
        session.onChange = { [weak self] snapshot in
            self?.publish(snapshot)
        }
        serve = session
        session.connect()
    }

    private func stopSessions() {
        rpc?.stop()
        serve?.stop()
        rpc = nil
        serve = nil
    }

    private func publish(_ snapshot: SessionSnapshot) {
        if Thread.isMainThread {
            self.snapshot = snapshot
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.snapshot = snapshot
            }
        }
    }
}
#endif
