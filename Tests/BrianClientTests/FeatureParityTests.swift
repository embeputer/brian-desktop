@testable import BrianClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

final class FeatureParityTests: XCTestCase {
    func testCliArgumentsUseTheRealCommands() throws {
        XCTAssertEqual(try BrianCli.arguments(for: .status), ["status", "--json"])
        XCTAssertEqual(try BrianCli.arguments(for: .skillList), ["skill", "list", "--json"])
        XCTAssertEqual(try BrianCli.arguments(for: .skillShow(name: "review")), ["skill", "show", "review"])
        XCTAssertEqual(
            try BrianCli.arguments(for: .skillNew(name: "review", description: "Look again")),
            ["skill", "new", "review", "--description", "Look again"]
        )
        XCTAssertEqual(
            try BrianCli.arguments(for: .memoryAdd(target: "People/Alex.md", content: "Studies CS")),
            ["memory", "add", "People/Alex", "-c", "Studies CS"]
        )
        XCTAssertEqual(
            try BrianCli.arguments(for: .routinesAdd(text: "Stand up", when: "tomorrow 9am", every: "daily", task: true)),
            ["routines", "add", "Stand up", "--when", "tomorrow 9am", "--every", "daily", "--task"]
        )
        XCTAssertEqual(
            try BrianCli.arguments(for: .mcpAddCommand(name: "files", command: ["npx", "-y", "server"])),
            ["mcp", "add", "files", "--", "npx", "-y", "server"]
        )
        XCTAssertEqual(
            try BrianCli.arguments(for: .mcpAddURL(name: "docs", url: "https://example.com/mcp")),
            ["mcp", "add", "docs", "--url", "https://example.com/mcp"]
        )
        XCTAssertEqual(try BrianCli.arguments(for: .mcpLogin(name: "docs")), ["mcp", "login", "docs"])
        XCTAssertEqual(
            try BrianCli.arguments(for: .modelSet(provider: "openrouter", modelID: "openai/gpt")),
            ["model", "openrouter/openai/gpt"]
        )
        let auth = try BrianCli.arguments(for: .authCheck(provider: "xai"))
        XCTAssertEqual(auth, ["auth", "check", "--provider", "xai", "--json", "--no-refresh"])
        XCTAssertFalse(auth.contains("--credentials"))
        XCTAssertEqual(
            try BrianCli.arguments(for: .connectBeeper(token: "tok", url: nil)),
            ["connect", "beeper", "--token", "tok"]
        )
        XCTAssertThrowsError(try BrianCli.arguments(for: .skillNew(name: "Not Valid", description: "x")))
        XCTAssertThrowsError(try BrianCli.arguments(for: .memoryAdd(target: "just-a-name", content: "x")))
    }

    func testParsersReadDocumentedJson() {
        let status = BrianCli.status(from: """
        {"version":"1.2.3","memoryNotes":4,"sessions":2,"skills":3,"defaultProvider":null,"defaultModel":"grok","background":"stopped"}
        """)
        XCTAssertEqual(status?.version, "1.2.3")
        XCTAssertEqual(status?.sessions, 2)
        XCTAssertNil(status?.defaultProvider)
        XCTAssertEqual(status?.defaultModel, "grok")

        let skills = BrianCli.skills(from: """
        [{"name":"review","description":"Look","filePath":"/skills/review/SKILL.md"}]
        """)
        XCTAssertEqual(skills?.first?.filePath, "/skills/review/SKILL.md")

        let notes = BrianCli.notes(from: """
        [{"name":"Alex","folder":"People","relativePath":"People/Alex.md","tags":["friend"],"people":[]}]
        """)
        XCTAssertEqual(notes?.first?.tags, ["friend"])

        let routines = BrianCli.routines(from: """
        [{"id":"r1","type":"reminder","payload":"Stand","when":"tomorrow 9am","recurrence":"","enabled":false}]
        """)
        XCTAssertEqual(routines?.first?.enabled, false)

        let mcp = BrianCli.mcp(from: """
        {"servers":[{"name":"docs","scope":"global","enabled":true,"state":"needs-auth","transport":"https://example.com/mcp","tools":["search"],"error":"sign in"}],"errors":["bad server"],"note":"project is untrusted"}
        """)
        XCTAssertEqual(mcp?.servers.first?.state, "needs-auth")
        XCTAssertEqual(mcp?.errors, ["bad server"])
        XCTAssertEqual(mcp?.note, "project is untrusted")

        XCTAssertNil(BrianCli.modelLine(from: "(not set)\n"))
        XCTAssertEqual(BrianCli.modelLine(from: "xai/grok-4\n"), "xai/grok-4")

        let auth = BrianCli.auth(from: """
        {"status":"not_ready","provider":"openai-codex","reason":"credentials_not_configured"}
        """)
        XCTAssertEqual(auth?.status, "not_ready")
        XCTAssertNil(auth?.authType)
    }

    func testCatalogKeepsJsonWhenTheCommandExitsNonZero() throws {
        let runner = CatalogRunner()
        runner.responses[["status", "--json"]] = output(
            #"{"version":"9","memoryNotes":1,"sessions":8,"skills":1,"defaultProvider":"xai","defaultModel":"grok","background":"stopped"}"#
        )
        runner.responses[["skill", "list", "--json"]] = output("[]")
        runner.responses[["memory", "list", "--json"]] = output("[]")
        runner.responses[["memory", "folders", "--json"]] = output(#"[{"folder":"People","notes":1}]"#)
        runner.responses[["routines", "list", "--json"]] = output("[]")
        runner.responses[["mcp", "list", "--json"]] = CommandOutput(
            status: 1,
            stdout: #"{"servers":[{"name":"docs","state":"failed","tools":[]}],"errors":["down"]}"#,
            stderr: ""
        )
        runner.responses[["model"]] = CommandOutput(status: 0, stdout: "(not set)\n", stderr: "")
        runner.responses[["auth", "check", "--provider", "xai", "--json", "--no-refresh"]] = CommandOutput(
            status: 1,
            stdout: #"{"status":"not_ready","provider":"xai","reason":"credentials_not_configured"}"#,
            stderr: ""
        )
        runner.responses[["auth", "check", "--provider", "openai-codex", "--json", "--no-refresh"]] = CommandOutput(
            status: 0,
            stdout: #"{"status":"ready","provider":"openai-codex","authType":"oauth"}"#,
            stderr: ""
        )
        let client = BrianCliClient(
            executable: URL(fileURLWithPath: "/usr/local/bin/brian"),
            workingDirectory: URL(fileURLWithPath: "/home/me"),
            environment: [:],
            runner: runner
        )
        let catalog = client.loadCatalog()
        XCTAssertEqual(catalog.status?.sessions, 8)
        XCTAssertEqual(catalog.mcp.servers.first?.name, "docs")
        XCTAssertEqual(catalog.mcp.errors, ["down"])
        XCTAssertNil(catalog.defaultModel)
        XCTAssertEqual(catalog.providers.map(\.provider), ["xai", "openai-codex"])
        XCTAssertEqual(catalog.folders.first?.notes, 1)
        XCTAssertTrue(catalog.problems.isEmpty, catalog.problems.joined(separator: "\n"))
        XCTAssertEqual(runner.directory, "/home/me")
        XCTAssertFalse(runner.calls.contains { $0.contains("--credentials") })
    }

    func testReducerStoresCommandsModelsAndSessions() {
        var reducer = RpcReducer()
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_state","success":true,"data":{"sessionId":"s","sessionFile":"/tmp/s.jsonl","sessionName":"Work","thinkingLevel":"high","model":{"provider":"xai","id":"grok"}}}"#
        ))
        XCTAssertEqual(reducer.snapshot.phase, .ready)
        XCTAssertEqual(reducer.snapshot.sessionName, "Work")
        XCTAssertEqual(reducer.snapshot.sessionFile, "/tmp/s.jsonl")
        XCTAssertEqual(reducer.snapshot.thinkingLevel, "high")
        XCTAssertEqual(reducer.snapshot.modelLabel, "xai / grok")

        reducer.noteOutgoingPrompt("Hi")
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_state","success":true,"data":{"sessionId":"s","model":{"provider":"xai","id":"grok"}}}"#
        ))
        XCTAssertEqual(reducer.snapshot.phase, .streaming)

        _ = reducer.apply(line(#"{"type":"agent_settled","aborted":false}"#))
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_commands","success":true,"data":{"commands":[{"name":"skill:review","description":"Look","source":"skill"}]}}"#
        ))
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_available_models","success":true,"data":{"models":[{"provider":"openai-codex","id":"gpt-5","name":"GPT-5","reasoning":true}]}}"#
        ))
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_available_thinking_levels","success":true,"data":{"levels":["off","high"]}}"#
        ))
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_fork_messages","success":true,"data":{"messages":[{"entryId":"e1","text":"Hi"}]}}"#
        ))
        XCTAssertEqual(reducer.snapshot.commands.first?.name, "skill:review")
        XCTAssertEqual(reducer.snapshot.models.first?.id, "openai-codex/gpt-5")
        XCTAssertEqual(reducer.snapshot.thinkingLevels, ["off", "high"])
        XCTAssertEqual(reducer.snapshot.forkPoints.first?.entryID, "e1")

        _ = reducer.apply(line(
            #"{"type":"response","command":"set_model","success":true,"data":{"provider":"openai-codex","id":"gpt-5"}}"#
        ))
        XCTAssertEqual(reducer.snapshot.modelLabel, "openai-codex / gpt-5")

        _ = reducer.apply(line(
            #"{"type":"response","command":"new_session","success":true,"data":{"cancelled":false}}"#
        ))
        XCTAssertTrue(reducer.snapshot.messages.isEmpty)
        XCTAssertEqual(reducer.snapshot.statusLine, "New session")
        _ = reducer.apply(line(
            #"{"type":"response","command":"get_messages","success":true,"data":{"messages":[{"role":"user","content":"kept"},{"role":"assistant","content":[{"type":"text","text":"back"}]}]}}"#
        ))
        XCTAssertEqual(reducer.snapshot.messages.filter { $0.role != .status }.map(\.text), ["kept", "back"])

        _ = reducer.apply(line(
            #"{"type":"response","command":"switch_session","success":true,"data":{"cancelled":true}}"#
        ))
        XCTAssertEqual(reducer.snapshot.messages.filter { $0.role != .status }.map(\.text), ["kept", "back"])
        XCTAssertTrue(reducer.snapshot.messages.contains { $0.text.contains("cancelled") })
    }

    func testSessionWritesRpcCommands() throws {
        let transport = FeatureTransport()
        let session = BrianSession(
            configuration: BrianLaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/brian"),
                arguments: ["--mode", "rpc"],
                workingDirectory: nil
            ),
            transport: transport
        )
        try session.start()
        try session.refreshCapabilities()
        try session.setModel(provider: "xai", modelID: "grok")
        try session.newSession()
        let types = try transport.written.map { try json($0)["type"] as? String }
        XCTAssertEqual(types, [
            "get_state",
            "get_state", "get_commands", "get_available_models", "get_available_thinking_levels", "get_fork_messages",
            "set_model", "get_state",
            "new_session", "get_messages", "get_state",
        ])
        let setModel = try json(transport.written[6])
        XCTAssertEqual(setModel["provider"] as? String, "xai")
        XCTAssertEqual(setModel["modelId"] as? String, "grok")
    }

    func testServeStatusSummary() throws {
        let summary = try XCTUnwrap(ServeStatusSummary.parse(Data(
            #"{"startedAt":"t","routines":3,"beeperConnected":true,"pendingDrafts":1}"#.utf8
        )))
        XCTAssertEqual(summary.routines, 3)
        XCTAssertTrue(summary.beeperConnected)
        XCTAssertEqual(summary.pendingDrafts, 1)
        XCTAssertNil(ServeStatusSummary.parse(Data(#"{"ok":true}"#.utf8)))

        let transport = StatusTransport()
        transport.result = .success((200, Data(#"{"routines":2,"beeperConnected":false,"pendingDrafts":0}"#.utf8)))
        let endpoint = try ServeAddress.parse(address: "127.0.0.1:7333", token: "secret").get()
        let session = ServeSession(endpoint: endpoint, transport: transport)
        session.fetchStatus()
        XCTAssertEqual(session.snapshot.remoteSummary, "2 routines · Beeper not connected · 0 drafts")
        XCTAssertEqual(transport.request?.url?.path, "/v1/status")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertEqual(session.snapshot.phase, .idle)
    }

    private func line(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func json(_ data: Data) throws -> [String: Any] {
        let body = data.last == 0x0A ? data.dropLast() : data
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }
}

private func output(_ text: String) -> CommandOutput {
    CommandOutput(status: 0, stdout: text, stderr: "")
}

private final class CatalogRunner: DirectoryCommandRunning {
    var calls: [[String]] = []
    var directory: String?
    var responses: [[String]: CommandOutput] = [:]

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?
    ) throws -> CommandOutput {
        calls.append(arguments)
        directory = currentDirectory?.path
        return responses[arguments] ?? CommandOutput(status: 1, stdout: "", stderr: "missing")
    }
}

private final class FeatureTransport: RpcTransport {
    var onStdout: ((Data) -> Void)?
    var onStderr: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    private(set) var written: [Data] = []

    func start() throws {}
    func write(_ data: Data) throws { written.append(data) }
    func closeInput() {}
    func terminate() {}
}

private final class StatusTransport: ServeTransport {
    var request: URLRequest?
    var result: Result<(Int, Data), Error> = .success((200, Data()))

    func send(request: URLRequest, completion: @escaping (Result<(Int, Data), Error>) -> Void) -> ServeTask {
        self.request = request
        completion(result)
        return StatusTask()
    }
}

private final class StatusTask: ServeTask {
    func cancel() {}
}
