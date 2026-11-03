import Foundation

public struct CommandOutput: Equatable, Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning: AnyObject {
    func run(executable: URL, arguments: [String], environment: [String: String]) throws -> CommandOutput
}

public final class ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String], environment: [String: String]) throws -> CommandOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()

        let stdout = PipeCollector()
        let stderr = PipeCollector()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stdout.collect(output.fileHandleForReading)
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderr.collect(error.fileHandleForReading)
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return CommandOutput(
            status: process.terminationStatus,
            stdout: String(data: stdout.data, encoding: .utf8) ?? "",
            stderr: String(data: stderr.data, encoding: .utf8) ?? ""
        )
    }
}

private final class PipeCollector: @unchecked Sendable {
    var data = Data()

    func collect(_ handle: FileHandle) {
        data = handle.readDataToEndOfFile()
    }
}

/// Finds `brian` on PATH, or installs the published CLI the way the harness documents.
public enum LocalBrianSetup {
    public static let packageName = "@brian-agent/cli"
    public static let installArguments = ["install", "-g", "--ignore-scripts", packageName]

    public static func resolveOrInstall(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: CommandRunning = ProcessCommandRunner(),
        locateBrian: (() -> URL?)? = nil,
        locateNpm: (() -> URL?)? = nil,
        isExecutable: ((String) -> Bool)? = nil
    ) throws -> URL {
        let executableCheck = isExecutable ?? { FileManager.default.isExecutableFile(atPath: $0) }
        let findBrian = locateBrian ?? {
            BrianExecutableResolver.resolve(explicitPath: nil, environment: environment)
        }
        let findNpm = locateNpm ?? {
            ExecutableSearch.find(named: "npm", environment: environment, isExecutable: executableCheck)
        }

        let trimmed = explicitPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            guard let url = BrianExecutableResolver.resolve(explicitPath: trimmed, environment: environment) else {
                throw BrianClientError(message: "Couldn't find \(trimmed).")
            }
            return url
        }
        if let found = findBrian() {
            return found
        }
        guard let npm = findNpm() else {
            throw BrianClientError(
                message: "brian is not installed, and npm was not found. Install Node.js 22.19 or newer, then try again."
            )
        }
        let installed = try runner.run(executable: npm, arguments: installArguments, environment: environment)
        guard installed.status == 0 else {
            throw BrianClientError(message: "Couldn't install brian. \(tail(installed.stderr))")
        }
        let prefix = try runner.run(executable: npm, arguments: ["prefix", "-g"], environment: environment)
        guard prefix.status == 0 else {
            throw BrianClientError(message: "Couldn't find npm's global bin directory. \(tail(prefix.stderr))")
        }
        let bin = URL(fileURLWithPath: prefix.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            .appendingPathComponent("bin/brian")
        if executableCheck(bin.path) {
            return bin
        }
        if let found = findBrian() {
            return found
        }
        throw BrianClientError(message: "npm finished, but brian is still not on PATH.")
    }

    private static func tail(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "npm failed." }
        if trimmed.count <= 500 { return trimmed }
        return String(trimmed.suffix(500))
    }
}
