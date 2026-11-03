import Foundation

public struct BrianLaunchConfiguration: Equatable, Sendable {
    public var executableURL: URL
    public var arguments: [String]
    public var workingDirectory: URL?
    public var extraEnvironment: [String: String]

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL?,
        extraEnvironment: [String: String] = [:]
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.extraEnvironment = extraEnvironment
    }

    /// `brian --mode rpc`, plus `--no-session` unless the caller already supplied arguments.
    ///
    /// `rpc-entry` injects `--mode rpc` itself, so this does not add the flag again.
    /// When `BRIAN_ARGS` is set it is the complete argument list and is not rewritten.
    public static func fromEnvironment(
        executableURL: URL,
        environment: [String: String],
        workingDirectory: URL?
    ) -> BrianLaunchConfiguration {
        if let raw = environment["BRIAN_ARGS"]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return BrianLaunchConfiguration(
                executableURL: executableURL,
                arguments: ArgumentSplitter.split(raw),
                workingDirectory: workingDirectory
            )
        }
        return rpcChild(executableURL: executableURL, workingDirectory: workingDirectory)
    }

    public static func rpcChild(
        executableURL: URL,
        extraArguments: [String] = ["--no-session"],
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:]
    ) -> BrianLaunchConfiguration {
        var arguments: [String] = []
        let name = executableURL.lastPathComponent
        let entryInjectsMode = name.contains("rpc-entry")
        if !entryInjectsMode, !extraArguments.contains("--mode") {
            arguments.append(contentsOf: ["--mode", "rpc"])
        }
        arguments.append(contentsOf: extraArguments)
        return BrianLaunchConfiguration(
            executableURL: executableURL,
            arguments: arguments,
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment
        )
    }
}

public enum BrianExecutableResolver {
    /// Resolve the `brian` binary.
    ///
    /// An explicit path or `BRIAN_BIN` wins. Otherwise the first executable named
    /// `brian` on `PATH`, then common macOS install locations, is used.
    /// GUI apps often inherit a short `PATH`, so those extra locations matter.
    public static func resolve(
        explicitPath: String? = nil,
        environment: [String: String]? = nil
    ) -> URL? {
        let environment = environment ?? ProcessInfo.processInfo.environment
        if let explicitPath {
            let trimmed = explicitPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return executableFile(expanding: trimmed)
            }
        }
        if let configured = environment["BRIAN_BIN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !configured.isEmpty {
            return executableFile(expanding: configured)
        }

        return ExecutableSearch.find(named: "brian", environment: environment)
    }

    static func executableFile(expanding path: String) -> URL? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }
}

enum ExecutableSearch {
    static func find(
        named name: String,
        environment: [String: String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        var directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = environment["HOME"] ?? ""
        directories.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
            "\(home)/bin",
        ])
        for directory in directories where !directory.isEmpty {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if isExecutable(path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}

protocol RpcTransport: AnyObject {
    var onStdout: ((Data) -> Void)? { get set }
    var onStderr: ((Data) -> Void)? { get set }
    var onExit: ((Int32) -> Void)? { get set }

    func start() throws
    func write(_ data: Data) throws
    func closeInput()
    func terminate()
}

final class ProcessRpcTransport: RpcTransport {
    var onStdout: ((Data) -> Void)?
    var onStderr: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    private let configuration: BrianLaunchConfiguration
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let error = Pipe()
    private var didStart = false

    init(configuration: BrianLaunchConfiguration) {
        self.configuration = configuration
    }

    func start() throws {
        if didStart {
            throw BrianClientError(message: "brian is already running.")
        }
        didStart = true
        process.executableURL = configuration.executableURL
        process.arguments = configuration.arguments
        if let workingDirectory = configuration.workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in configuration.extraEnvironment {
            environment[key] = value
        }
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.terminationHandler = { [weak self] process in
            self?.onExit?(process.terminationStatus)
        }
        readLoop(output.fileHandleForReading) { [weak self] data in
            self?.onStdout?(data)
        }
        readLoop(error.fileHandleForReading) { [weak self] data in
            self?.onStderr?(data)
        }
        do {
            try process.run()
        } catch {
            throw BrianClientError(message: "Could not start \(configuration.executableURL.path). \(error.localizedDescription)")
        }
    }

    func write(_ data: Data) throws {
        guard process.isRunning else {
            throw BrianClientError(message: "brian is not running.")
        }
        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            throw BrianClientError(message: "Could not write to brian. \(error.localizedDescription)")
        }
    }

    func closeInput() {
        try? input.fileHandleForWriting.close()
    }

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    private func readLoop(_ handle: FileHandle, deliver: @escaping (Data) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            while true {
                let data = handle.availableData
                deliver(data)
                if data.isEmpty {
                    break
                }
            }
        }
    }
}
