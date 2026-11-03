import Foundation

public protocol DirectoryCommandRunning: AnyObject {
    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?
    ) throws -> CommandOutput
}

extension ProcessCommandRunner: DirectoryCommandRunning {}

public struct BrianStatus: Equatable, Sendable {
    public var version: String
    public var memoryNotes: Int
    public var sessions: Int
    public var skills: Int
    public var defaultProvider: String?
    public var defaultModel: String?
    public var background: String

    public init(
        version: String,
        memoryNotes: Int,
        sessions: Int,
        skills: Int,
        defaultProvider: String?,
        defaultModel: String?,
        background: String
    ) {
        self.version = version
        self.memoryNotes = memoryNotes
        self.sessions = sessions
        self.skills = skills
        self.defaultProvider = defaultProvider
        self.defaultModel = defaultModel
        self.background = background
    }
}

public struct BrianSkill: Equatable, Sendable, Identifiable {
    public var name: String
    public var description: String
    public var filePath: String

    public var id: String { name }

    public init(name: String, description: String, filePath: String) {
        self.name = name
        self.description = description
        self.filePath = filePath
    }
}

public struct MemoryNoteSummary: Equatable, Sendable, Identifiable {
    public var name: String
    public var folder: String
    public var relativePath: String
    public var tags: [String]
    public var people: [String]

    public var id: String { relativePath }

    public init(name: String, folder: String, relativePath: String, tags: [String], people: [String]) {
        self.name = name
        self.folder = folder
        self.relativePath = relativePath
        self.tags = tags
        self.people = people
    }
}

public struct MemoryFolder: Equatable, Sendable, Identifiable {
    public var folder: String
    public var notes: Int

    public var id: String { folder }

    public init(folder: String, notes: Int) {
        self.folder = folder
        self.notes = notes
    }
}

public struct RoutineSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var payload: String
    public var when: String
    public var recurrence: String
    public var enabled: Bool

    public init(id: String, type: String, payload: String, when: String, recurrence: String, enabled: Bool) {
        self.id = id
        self.type = type
        self.payload = payload
        self.when = when
        self.recurrence = recurrence
        self.enabled = enabled
    }
}

public struct McpServerSummary: Equatable, Sendable, Identifiable {
    public var name: String
    public var scope: String
    public var enabled: Bool
    public var state: String
    public var transport: String
    public var tools: [String]
    public var error: String?

    public var id: String { "\(scope)/\(name)" }

    public init(
        name: String,
        scope: String,
        enabled: Bool,
        state: String,
        transport: String,
        tools: [String],
        error: String?
    ) {
        self.name = name
        self.scope = scope
        self.enabled = enabled
        self.state = state
        self.transport = transport
        self.tools = tools
        self.error = error
    }
}

public struct McpCatalog: Equatable, Sendable {
    public var servers: [McpServerSummary]
    public var errors: [String]
    public var note: String?

    public init(servers: [McpServerSummary], errors: [String], note: String?) {
        self.servers = servers
        self.errors = errors
        self.note = note
    }
}

public struct ProviderAuth: Equatable, Sendable, Identifiable {
    public var provider: String
    public var status: String
    public var reason: String?
    public var authType: String?

    public var id: String { provider }

    public init(provider: String, status: String, reason: String?, authType: String?) {
        self.provider = provider
        self.status = status
        self.reason = reason
        self.authType = authType
    }
}

public struct BrianCatalog: Equatable, Sendable {
    public var status: BrianStatus?
    public var skills: [BrianSkill]
    public var notes: [MemoryNoteSummary]
    public var folders: [MemoryFolder]
    public var routines: [RoutineSummary]
    public var mcp: McpCatalog
    public var defaultModel: String?
    public var providers: [ProviderAuth]
    public var problems: [String]

    public init(
        status: BrianStatus?,
        skills: [BrianSkill],
        notes: [MemoryNoteSummary],
        folders: [MemoryFolder],
        routines: [RoutineSummary],
        mcp: McpCatalog,
        defaultModel: String?,
        providers: [ProviderAuth],
        problems: [String]
    ) {
        self.status = status
        self.skills = skills
        self.notes = notes
        self.folders = folders
        self.routines = routines
        self.mcp = mcp
        self.defaultModel = defaultModel
        self.providers = providers
        self.problems = problems
    }
}

public enum BrianCliCommand: Equatable, Sendable {
    case status
    case skillList
    case skillShow(name: String)
    case skillAdd(source: String, force: Bool)
    case skillNew(name: String, description: String)
    case skillRemove(name: String)
    case memoryList(folder: String?)
    case memorySearch(text: String)
    case memoryFolders
    case memoryShow(note: String)
    case memoryAdd(target: String, content: String)
    case routinesList
    case routinesAdd(text: String, when: String, every: String?, task: Bool)
    case routinesRemove(id: String)
    case routinesPause(id: String)
    case routinesResume(id: String)
    case routinesHistory(id: String?)
    case routinesRun(id: String)
    case mcpList
    case mcpAddCommand(name: String, command: [String])
    case mcpAddURL(name: String, url: String)
    case mcpRemove(name: String)
    case mcpLogin(name: String)
    case mcpLogout(name: String)
    case model
    case modelSet(provider: String, modelID: String)
    case authCheck(provider: String)
    case connectBeeper(token: String, url: String?)
}

public enum BrianCli {
    public static let connectionProviders = ["xai", "openai-codex"]

    public static func arguments(for command: BrianCliCommand) throws -> [String] {
        switch command {
        case .status:
            return ["status", "--json"]
        case .skillList:
            return ["skill", "list", "--json"]
        case .skillShow(let name):
            return ["skill", "show", try skillName(name)]
        case .skillAdd(let source, let force):
            let path = try required(source, label: "a skill file or directory")
            return ["skill", "add", path] + (force ? ["--force"] : [])
        case .skillNew(let name, let description):
            let text = try required(description, label: "a description")
            return ["skill", "new", try skillName(name), "--description", text]
        case .skillRemove(let name):
            return ["skill", "remove", try skillName(name)]
        case .memoryList(let folder):
            var arguments = ["memory", "list", "--json"]
            if let folder = nonEmpty(folder) {
                arguments += ["-f", folder]
            }
            return arguments
        case .memorySearch(let text):
            let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                return ["memory", "search", "--json"]
            }
            return ["memory", "search", query, "--json"]
        case .memoryFolders:
            return ["memory", "folders", "--json"]
        case .memoryShow(let note):
            return ["memory", "show", try required(note, label: "a note")]
        case .memoryAdd(let target, let content):
            let note = try memoryTarget(target)
            return ["memory", "add", note, "-c", content]
        case .routinesList:
            return ["routines", "list", "--json"]
        case .routinesAdd(let text, let when, let every, let task):
            var arguments = [
                "routines", "add",
                try required(text, label: "routine text"),
                "--when", try required(when, label: "a time"),
            ]
            if let every = nonEmpty(every) {
                arguments += ["--every", every]
            }
            if task {
                arguments.append("--task")
            }
            return arguments
        case .routinesRemove(let id):
            return ["routines", "remove", try required(id, label: "a routine id")]
        case .routinesPause(let id):
            return ["routines", "pause", try required(id, label: "a routine id")]
        case .routinesResume(let id):
            return ["routines", "resume", try required(id, label: "a routine id")]
        case .routinesHistory(let id):
            return ["routines", "history"] + (nonEmpty(id).map { [$0] } ?? [])
        case .routinesRun(let id):
            return ["routines", "run", try required(id, label: "a routine id")]
        case .mcpList:
            return ["mcp", "list", "--json"]
        case .mcpAddCommand(let name, let command):
            let server = try required(name, label: "a server name")
            let tokens = command.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !tokens.isEmpty else {
                throw BrianClientError(message: "An MCP command needs a program to run.")
            }
            return ["mcp", "add", server, "--"] + tokens
        case .mcpAddURL(let name, let url):
            return ["mcp", "add", try required(name, label: "a server name"), "--url", try required(url, label: "a URL")]
        case .mcpRemove(let name):
            return ["mcp", "remove", try required(name, label: "a server name")]
        case .mcpLogin(let name):
            return ["mcp", "login", try required(name, label: "a server name")]
        case .mcpLogout(let name):
            return ["mcp", "logout", try required(name, label: "a server name")]
        case .model:
            return ["model"]
        case .modelSet(let provider, let modelID):
            let providerID = try required(provider, label: "a provider")
            let model = try required(modelID, label: "a model id")
            guard !providerID.contains("/") else {
                throw BrianClientError(message: "The provider is the part before the first slash.")
            }
            return ["model", "\(providerID)/\(model)"]
        case .authCheck(let provider):
            return ["auth", "check", "--provider", try required(provider, label: "a provider"), "--json", "--no-refresh"]
        case .connectBeeper(let token, let url):
            var arguments = ["connect", "beeper", "--token", try required(token, label: "a Beeper token")]
            if let url = nonEmpty(url) {
                arguments += ["--url", url]
            }
            return arguments
        }
    }

    public static func status(from stdout: String) -> BrianStatus? {
        guard let object = object(from: stdout) else { return nil }
        guard JSONLookup.string(object["version"]) != nil || object["sessions"] != nil else { return nil }
        return BrianStatus(
            version: JSONLookup.string(object["version"]) ?? "",
            memoryNotes: JSONLookup.int(object["memoryNotes"]) ?? 0,
            sessions: JSONLookup.int(object["sessions"]) ?? 0,
            skills: JSONLookup.int(object["skills"]) ?? 0,
            defaultProvider: JSONLookup.string(object["defaultProvider"]),
            defaultModel: JSONLookup.string(object["defaultModel"]),
            background: JSONLookup.string(object["background"]) ?? ""
        )
    }

    public static func skills(from stdout: String) -> [BrianSkill]? {
        guard let items = array(from: stdout) else { return nil }
        return items.compactMap { item in
            guard let object = JSONLookup.object(item), let name = JSONLookup.string(object["name"]) else { return nil }
            return BrianSkill(
                name: name,
                description: JSONLookup.string(object["description"]) ?? "",
                filePath: JSONLookup.string(object["filePath"]) ?? ""
            )
        }
    }

    public static func notes(from stdout: String) -> [MemoryNoteSummary]? {
        guard let items = array(from: stdout) else { return nil }
        return items.compactMap { item in
            guard let object = JSONLookup.object(item), let name = JSONLookup.string(object["name"]) else { return nil }
            let relative = JSONLookup.string(object["relativePath"]) ?? name
            return MemoryNoteSummary(
                name: name,
                folder: JSONLookup.string(object["folder"]) ?? "",
                relativePath: relative,
                tags: JSONLookup.strings(object["tags"]),
                people: JSONLookup.strings(object["people"])
            )
        }
    }

    public static func folders(from stdout: String) -> [MemoryFolder]? {
        guard let items = array(from: stdout) else { return nil }
        return items.compactMap { item in
            guard let object = JSONLookup.object(item), let folder = JSONLookup.string(object["folder"]) else { return nil }
            return MemoryFolder(folder: folder, notes: JSONLookup.int(object["notes"]) ?? 0)
        }
    }

    public static func routines(from stdout: String) -> [RoutineSummary]? {
        guard let items = array(from: stdout) else { return nil }
        return items.compactMap { item in
            guard let object = JSONLookup.object(item), let id = JSONLookup.string(object["id"]) else { return nil }
            return RoutineSummary(
                id: id,
                type: JSONLookup.string(object["type"]) ?? "",
                payload: JSONLookup.string(object["payload"]) ?? "",
                when: JSONLookup.string(object["when"]) ?? "",
                recurrence: JSONLookup.string(object["recurrence"]) ?? "",
                enabled: JSONLookup.bool(object["enabled"]) ?? true
            )
        }
    }

    public static func mcp(from stdout: String) -> McpCatalog? {
        guard let object = object(from: stdout), let servers = JSONLookup.array(object["servers"]) else { return nil }
        let parsed = servers.compactMap { item -> McpServerSummary? in
            guard let server = JSONLookup.object(item), let name = JSONLookup.string(server["name"]) else { return nil }
            return McpServerSummary(
                name: name,
                scope: JSONLookup.string(server["scope"]) ?? "global",
                enabled: JSONLookup.bool(server["enabled"]) ?? true,
                state: JSONLookup.string(server["state"]) ?? "",
                transport: JSONLookup.string(server["transport"]) ?? "",
                tools: JSONLookup.strings(server["tools"]),
                error: JSONLookup.string(server["error"])
            )
        }
        let note = JSONLookup.string(object["note"])
        return McpCatalog(servers: parsed, errors: JSONLookup.strings(object["errors"]), note: note)
    }

    public static func modelLine(from stdout: String) -> String? {
        let line = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line == "(not set)" {
            return nil
        }
        return line
    }

    public static func auth(from stdout: String) -> ProviderAuth? {
        guard let object = object(from: stdout),
              let provider = JSONLookup.string(object["provider"]),
              let status = JSONLookup.string(object["status"])
        else { return nil }
        return ProviderAuth(
            provider: provider,
            status: status,
            reason: JSONLookup.string(object["reason"]),
            authType: JSONLookup.string(object["authType"])
        )
    }

    private static func object(from stdout: String) -> [String: Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return JSONLookup.object(from: data)
    }

    private static func array(from stdout: String) -> [Any]? {
        guard let data = stdout.data(using: .utf8) else { return nil }
        return JSONLookup.array(from: data)
    }

    private static func required(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BrianClientError(message: "That needs \(label).")
        }
        return trimmed
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func skillName(_ value: String) throws -> String {
        let name = try required(value, label: "a skill name")
        let pattern = #"^[a-z0-9][a-z0-9-]*$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else {
            throw BrianClientError(message: "Skill names use lowercase letters, digits, and hyphens.")
        }
        return name
    }

    private static func memoryTarget(_ value: String) throws -> String {
        let target = try required(value, label: "Folder/Name").replacingOccurrences(of: ".md", with: "", options: .caseInsensitive)
        let slash = target.lastIndex(of: "/")
        guard let slash, slash != target.startIndex, target.index(after: slash) != target.endIndex else {
            throw BrianClientError(message: "A memory note needs Folder/Name.")
        }
        return target
    }
}

public final class BrianCliClient {
    private let executable: URL
    private let workingDirectory: URL
    private let environment: [String: String]
    private let runner: DirectoryCommandRunning

    public init(
        executable: URL,
        workingDirectory: URL,
        environment: [String: String],
        runner: DirectoryCommandRunning
    ) {
        self.executable = executable
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.runner = runner
    }

    public func run(_ command: BrianCliCommand) throws -> CommandOutput {
        let arguments = try BrianCli.arguments(for: command)
        return try runner.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: workingDirectory
        )
    }

    public func loadCatalog() -> BrianCatalog {
        var problems: [String] = []
        func take(_ command: BrianCliCommand, fallback: String) -> CommandOutput? {
            do {
                return try run(command)
            } catch {
                problems.append(error.localizedDescription)
                return nil
            }
        }
        func parsed<T>(_ command: BrianCliCommand, fallback: String, parse: (String) -> T?) -> T? {
            guard let output = take(command, fallback: fallback) else { return nil }
            if let value = parse(output.stdout) {
                return value
            }
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            problems.append(detail.isEmpty ? fallback : detail)
            return nil
        }

        let status = parsed(.status, fallback: "Couldn't read brian status.") { BrianCli.status(from: $0) }
        let skills = parsed(.skillList, fallback: "Couldn't list skills.") { BrianCli.skills(from: $0) } ?? []
        let notes = parsed(.memoryList(folder: nil), fallback: "Couldn't list memory.") { BrianCli.notes(from: $0) } ?? []
        let folders = parsed(.memoryFolders, fallback: "Couldn't list memory folders.") { BrianCli.folders(from: $0) } ?? []
        let routines = parsed(.routinesList, fallback: "Couldn't list routines.") { BrianCli.routines(from: $0) } ?? []
        let mcp = parsed(.mcpList, fallback: "Couldn't list MCP servers.") { BrianCli.mcp(from: $0) }
            ?? McpCatalog(servers: [], errors: [], note: nil)
        let defaultModel = parsed(.model, fallback: "Couldn't read the default model.") { stdout in
            BrianCli.modelLine(from: stdout) ?? ""
        }
        var providers: [ProviderAuth] = []
        for provider in BrianCli.connectionProviders {
            if let auth = parsed(.authCheck(provider: provider), fallback: "Couldn't check \(provider).", parse: BrianCli.auth(from:)) {
                providers.append(auth)
            }
        }
        return BrianCatalog(
            status: status,
            skills: skills,
            notes: notes,
            folders: folders,
            routines: routines,
            mcp: mcp,
            defaultModel: defaultModel?.isEmpty == true ? nil : defaultModel,
            providers: providers,
            problems: problems
        )
    }
}

public struct ServeStatusSummary: Equatable, Sendable {
    public var routines: Int
    public var beeperConnected: Bool
    public var pendingDrafts: Int
    public var line: String

    public init(routines: Int, beeperConnected: Bool, pendingDrafts: Int, line: String) {
        self.routines = routines
        self.beeperConnected = beeperConnected
        self.pendingDrafts = pendingDrafts
        self.line = line
    }

    public static func parse(_ data: Data) -> ServeStatusSummary? {
        guard let object = JSONLookup.object(from: data) else { return nil }
        guard object["routines"] != nil || object["beeperConnected"] != nil || object["pendingDrafts"] != nil else {
            return nil
        }
        let routines = JSONLookup.int(object["routines"]) ?? 0
        let beeper = JSONLookup.bool(object["beeperConnected"]) ?? false
        let drafts = JSONLookup.int(object["pendingDrafts"]) ?? 0
        let line = "\(routines) routines · Beeper \(beeper ? "connected" : "not connected") · \(drafts) drafts"
        return ServeStatusSummary(routines: routines, beeperConnected: beeper, pendingDrafts: drafts, line: line)
    }
}
