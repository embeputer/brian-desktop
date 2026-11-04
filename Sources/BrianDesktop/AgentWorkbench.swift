#if os(macOS)
import BrianClient
import Foundation

@MainActor
final class AgentWorkbench: ObservableObject {
    @Published private(set) var status: BrianStatus?
    @Published private(set) var skills: [BrianSkill] = []
    @Published private(set) var notes: [MemoryNoteSummary] = []
    @Published private(set) var folders: [MemoryFolder] = []
    @Published private(set) var routines: [RoutineSummary] = []
    @Published private(set) var mcp = McpCatalog(servers: [], errors: [], note: nil)
    @Published private(set) var defaultModel: String?
    @Published private(set) var providers: [ProviderAuth] = []
    @Published private(set) var searchResults: [MemoryNoteSummary] = []
    @Published private(set) var notice = ""
    @Published private(set) var busy = false

    func reload(executablePath: String, workingDirectory: URL) {
        run(nil, executablePath: executablePath, workingDirectory: workingDirectory, reloadAfter: true)
    }

    func perform(_ command: BrianCliCommand, executablePath: String, workingDirectory: URL) {
        run(command, executablePath: executablePath, workingDirectory: workingDirectory, reloadAfter: true)
    }

    func capture(_ command: BrianCliCommand, executablePath: String, workingDirectory: URL) {
        run(command, executablePath: executablePath, workingDirectory: workingDirectory, reloadAfter: false)
    }

    func searchMemory(text: String, executablePath: String, workingDirectory: URL) {
        let path = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            notice = "Brian is not running on this Mac."
            return
        }
        guard !busy else { return }
        busy = true
        let environment = ProcessInfo.processInfo.environment
        DispatchQueue.global(qos: .userInitiated).async {
            let client = Self.client(path: path, workingDirectory: workingDirectory, environment: environment)
            let result = Result { try client.run(.memorySearch(text: text)) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.busy = false
                switch result {
                case .failure(let error):
                    self.notice = error.localizedDescription
                case .success(let output):
                    let notes = BrianCli.notes(from: output.stdout) ?? []
                    self.searchResults = notes
                    if notes.isEmpty {
                        self.notice = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "No matching notes."
                            : output.stderr
                    } else {
                        self.notice = "\(notes.count) matching notes."
                    }
                }
            }
        }
    }

    private func run(
        _ command: BrianCliCommand?,
        executablePath: String,
        workingDirectory: URL,
        reloadAfter: Bool
    ) {
        let path = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            notice = "Brian is not running on this Mac."
            return
        }
        guard !busy else { return }
        busy = true
        let environment = ProcessInfo.processInfo.environment
        DispatchQueue.global(qos: .userInitiated).async {
            let client = Self.client(path: path, workingDirectory: workingDirectory, environment: environment)
            var commandNotice: String?
            if let command {
                do {
                    commandNotice = Self.describe(try client.run(command))
                } catch {
                    commandNotice = error.localizedDescription
                }
            }
            let catalog = reloadAfter ? client.loadCatalog() : nil
            DispatchQueue.main.async { [weak self] in
                self?.apply(catalog: catalog, commandNotice: commandNotice)
            }
        }
    }

    private func apply(catalog: BrianCatalog?, commandNotice: String?) {
        busy = false
        if let catalog {
            status = catalog.status
            skills = catalog.skills
            notes = catalog.notes
            folders = catalog.folders
            routines = catalog.routines
            mcp = catalog.mcp
            defaultModel = catalog.defaultModel
            providers = catalog.providers
        }
        var lines: [String] = []
        if let commandNotice, !commandNotice.isEmpty {
            lines.append(commandNotice)
        }
        if let catalog {
            lines.append(contentsOf: catalog.problems)
        }
        notice = lines.joined(separator: "\n")
    }

    private static func client(path: String, workingDirectory: URL, environment: [String: String]) -> BrianCliClient {
        BrianCliClient(
            executable: URL(fileURLWithPath: path),
            workingDirectory: workingDirectory,
            environment: environment,
            runner: ProcessCommandRunner()
        )
    }

    private static func describe(_ output: CommandOutput) -> String {
        let out = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if output.status == 0 {
            text = out.isEmpty ? "Done." : out
        } else if !err.isEmpty {
            text = err
        } else if !out.isEmpty {
            text = out
        } else {
            text = "brian exited \(output.status)."
        }
        if text.count > 4_000 {
            return String(text.suffix(4_000))
        }
        return text
    }
}
#endif
