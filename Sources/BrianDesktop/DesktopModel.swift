#if os(macOS)
import BrianClient
import Foundation

@MainActor
final class DesktopModel: ObservableObject {
    @Published private(set) var snapshot: SessionSnapshot = .disconnected
    @Published var prompt = ""
    @Published var executablePath = ""

    private var session: BrianSession?
    private let defaultsKey = "dev.brian.desktop.executable"
    private let workingDirectory: URL

    init() {
        workingDirectory = FileManager.default.homeDirectoryForCurrentUser
        if let saved = UserDefaults.standard.string(forKey: defaultsKey), !saved.isEmpty {
            executablePath = saved
        } else if let found = BrianExecutableResolver.resolve() {
            executablePath = found.path
        }
    }

    var workingDirectoryPath: String { workingDirectory.path }

    func connectIfNeeded() {
        if session == nil {
            connect()
        }
    }

    func connect() {
        session?.stop()
        session = nil
        let explicit = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let executable = BrianExecutableResolver.resolve(explicitPath: explicit.isEmpty ? nil : explicit) else {
            snapshot = SessionSnapshot(
                phase: .failed("Couldn't find the brian executable."),
                messages: snapshot.messages,
                statusLine: "Couldn't find the brian executable.",
                stderr: snapshot.stderr,
                modelLabel: nil,
                sessionID: nil
            )
            return
        }
        executablePath = executable.path
        UserDefaults.standard.set(executable.path, forKey: defaultsKey)
        let configuration = BrianLaunchConfiguration.fromEnvironment(
            executableURL: executable,
            environment: ProcessInfo.processInfo.environment,
            workingDirectory: workingDirectory
        )
        let session = BrianSession(configuration: configuration)
        session.onChange = { [weak self] snapshot in
            self?.publish(snapshot)
        }
        self.session = session
        do {
            try session.start()
        } catch {
            publish(session.snapshot)
        }
    }

    func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try session?.sendPrompt(text)
            prompt = ""
        } catch {
            snapshot.statusLine = error.localizedDescription
        }
    }

    func abort() {
        try? session?.abort()
    }

    func stop() {
        session?.stop()
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
