@testable import BrianClient
import Foundation
import XCTest

final class BrianClientTests: XCTestCase {
    func testFramerSplitsOnLineFeedOnly() {
        var framer = JsonlFramer()
        let first = framer.append(Data("{\"a\":1}\n{\"b\"".utf8))
        XCTAssertEqual(first.map(text), ["{\"a\":1}"])
        let second = framer.append(Data(":2}\r\n".utf8))
        XCTAssertEqual(second.map(text), ["{\"b\":2}"])

        var unicode = JsonlFramer()
        let payload = "{\"t\":\"a\u{2028}b\"}\n".data(using: .utf8)!
        let lines = unicode.append(payload)
        XCTAssertEqual(lines.count, 1)
        let object = try? JSONSerialization.jsonObject(with: lines[0]) as? [String: String]
        XCTAssertEqual(object?["t"], "a\u{2028}b")

        var tail = JsonlFramer()
        XCTAssertTrue(tail.append(Data("{\"c\":3}".utf8)).isEmpty)
        XCTAssertEqual(tail.finish().map(text), ["{\"c\":3}"])
    }

    func testLaunchArguments() {
        let brian = URL(fileURLWithPath: "/usr/local/bin/brian")
        XCTAssertEqual(
            BrianLaunchConfiguration.rpcChild(executableURL: brian).arguments,
            ["--mode", "rpc", "--no-session"]
        )
        let entry = URL(fileURLWithPath: "/opt/brian/rpc-entry.js")
        XCTAssertEqual(
            BrianLaunchConfiguration.rpcChild(executableURL: entry).arguments,
            ["--no-session"]
        )
        XCTAssertEqual(
            BrianLaunchConfiguration.rpcChild(executableURL: brian, extraArguments: ["--mode", "rpc", "--model", "x"]).arguments,
            ["--mode", "rpc", "--model", "x"]
        )
        let custom = BrianLaunchConfiguration.fromEnvironment(
            executableURL: URL(fileURLWithPath: "/usr/bin/node"),
            environment: ["BRIAN_ARGS": "\"/src/cli.js\" --mode rpc --no-session"],
            workingDirectory: nil
        )
        XCTAssertEqual(custom.arguments, ["/src/cli.js", "--mode", "rpc", "--no-session"])
    }

    func testArgumentSplitterKeepsQuotedPaths() {
        XCTAssertEqual(
            ArgumentSplitter.split(#""/path/with space/cli.js" --no-session"#),
            ["/path/with space/cli.js", "--no-session"]
        )
    }

    func testResolverFindsPathEntryAndHonorsExplicitMiss() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("brian")
        try "#!/bin/sh\nexit 0\n".write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)

        let resolved = BrianExecutableResolver.resolve(
            environment: ["PATH": directory.path, "HOME": "/nowhere"]
        )
        XCTAssertEqual(resolved?.path, binary.path)

        let missing = BrianExecutableResolver.resolve(
            explicitPath: directory.appendingPathComponent("missing").path,
            environment: ["PATH": directory.path, "HOME": "/nowhere"]
        )
        XCTAssertNil(missing)
    }

    func testReducerStreamsTextAndKeepsDelivery() throws {
        var reducer = RpcReducer()
        _ = reducer.apply(jsonLine(
            #"{"id":"req_1","type":"response","command":"get_state","success":true,"data":{"sessionId":"s","model":{"provider":"anthropic","id":"claude"}}}"#
        ))
        XCTAssertEqual(reducer.snapshot.phase, .ready)
        XCTAssertEqual(reducer.snapshot.modelLabel, "anthropic / claude")

        reducer.noteOutgoingPrompt("Hi")
        _ = reducer.apply(jsonLine(
            #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hel"}}"#
        ))
        _ = reducer.apply(jsonLine(
            #"{"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"lo"}}"#
        ))
        XCTAssertEqual(assistantText(reducer.snapshot), "Hello")
        XCTAssertEqual(reducer.snapshot.phase, .streaming)

        _ = reducer.apply(jsonLine(
            #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"Hello there"}],"stopReason":"stop"}}"#
        ))
        _ = reducer.apply(jsonLine(
            #"{"type":"delivery","delivery":{"text":"Hello there","embeds":[{"title":"later"}],"questions":[],"attachments":[],"errors":[]}}"#
        ))
        _ = reducer.apply(jsonLine(#"{"type":"agent_settled","aborted":false}"#))

        let assistant = try XCTUnwrap(reducer.snapshot.messages.last { $0.role == .assistant })
        XCTAssertEqual(assistant.text, "Hello there")
        XCTAssertTrue(assistant.isComplete)
        XCTAssertTrue(assistant.deliveryJSON?.contains("later") == true)
        XCTAssertEqual(reducer.snapshot.phase, .ready)
        XCTAssertEqual(reducer.snapshot.messages.first?.role, .user)
    }

    func testLatePromptAcceptanceDoesNotRestartASettledRun() {
        var reducer = RpcReducer()
        reducer.noteOutgoingPrompt("Hi")
        _ = reducer.apply(jsonLine(#"{"type":"agent_settled","aborted":false}"#))
        _ = reducer.apply(jsonLine(
            #"{"id":"req_2","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}"#
        ))
        XCTAssertEqual(reducer.snapshot.phase, .ready)
    }

    func testReducerSurfacesPromptRejection() {
        var reducer = RpcReducer()
        reducer.noteOutgoingPrompt("Hi")
        _ = reducer.apply(jsonLine(
            #"{"id":"req_2","type":"response","command":"prompt","success":false,"error":"Model not found"}"#
        ))
        XCTAssertEqual(reducer.snapshot.phase, .ready)
        XCTAssertTrue(reducer.snapshot.messages.contains { $0.role == .status && $0.text == "Model not found" })
    }

    func testPromptCommandIsOneJSONLine() throws {
        let transport = ScriptedTransport()
        let session = BrianSession(
            configuration: BrianLaunchConfiguration(
                executableURL: URL(fileURLWithPath: "/usr/bin/brian"),
                arguments: ["--mode", "rpc", "--no-session"],
                workingDirectory: nil
            ),
            transport: transport
        )
        try session.start()
        try session.sendPrompt("a\nb")
        XCTAssertEqual(transport.written.count, 2)
        for data in transport.written {
            XCTAssertEqual(data.last, 0x0A)
            XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)
        }
        let state = try jsonObject(transport.written[0])
        XCTAssertEqual(state["type"] as? String, "get_state")
        XCTAssertEqual(state["id"] as? String, "req_1")
        let prompt = try jsonObject(transport.written[1])
        XCTAssertEqual(prompt["type"] as? String, "prompt")
        XCTAssertEqual(prompt["id"] as? String, "req_2")
        XCTAssertEqual(prompt["message"] as? String, "a\nb")

        transport.emit(#"{"type":"extension_ui_request","id":"ui-1","method":"confirm","title":"Run it?","message":"yes"}"#)
        XCTAssertEqual(transport.written.count, 3)
        let cancel = try jsonObject(transport.written[2])
        XCTAssertEqual(cancel["type"] as? String, "extension_ui_response")
        XCTAssertEqual(cancel["id"] as? String, "ui-1")
        XCTAssertEqual(cancel["cancelled"] as? Bool, true)
        XCTAssertTrue(session.snapshot.messages.contains { $0.text.contains("Run it?") })
    }

    func testChildProcessStreamsSplitRecord() throws {
        let node = try nodeExecutable()
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-brian.mjs")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.path))

        let session = BrianSession(
            configuration: BrianLaunchConfiguration(
                executableURL: node,
                arguments: [fixture.path],
                workingDirectory: fixture.deletingLastPathComponent()
            )
        )
        defer { session.stop() }
        try session.start()
        waitUntil { session.snapshot.modelLabel == "fake / fake-1" && session.snapshot.phase == .ready }
        XCTAssertEqual(session.snapshot.modelLabel, "fake / fake-1")
        XCTAssertEqual(session.snapshot.sessionID, "sess-test")

        try session.sendPrompt("Say hello")
        waitUntil {
            session.snapshot.messages.contains { message in
                message.role == .assistant && message.text.contains("\u{2028}") && !message.isComplete
            }
        }
        XCTAssertTrue(session.snapshot.messages.contains { $0.role == .assistant && $0.text == "Hello \u{2028}world" })

        waitUntil {
            session.snapshot.phase == .ready
                && session.snapshot.messages.contains { $0.role == .assistant && $0.text == "FINAL" && $0.isComplete }
        }
        let assistant = try XCTUnwrap(session.snapshot.messages.last { $0.role == .assistant })
        XCTAssertEqual(assistant.text, "FINAL")
        XCTAssertTrue(assistant.deliveryJSON?.contains("later") == true)
        XCTAssertTrue(session.snapshot.stderr.contains("ready"))
    }

    private func nodeExecutable() throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent("node")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        throw XCTSkip("node is not on PATH")
    }

    private func waitUntil(timeout: TimeInterval = 5, _ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func jsonLine(_ json: String) -> Data {
        Data(json.utf8)
    }

    private func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        let body = data.last == 0x0A ? data.dropLast() : data
        let value = try JSONSerialization.jsonObject(with: body)
        return try XCTUnwrap(value as? [String: Any])
    }

    private func assistantText(_ snapshot: SessionSnapshot) -> String? {
        snapshot.messages.last { $0.role == .assistant }?.text
    }
}

private final class ScriptedTransport: RpcTransport {
    var onStdout: ((Data) -> Void)?
    var onStderr: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?
    private(set) var written: [Data] = []

    func start() throws {}

    func write(_ data: Data) throws {
        written.append(data)
    }

    func closeInput() {}

    func terminate() {}

    func emit(_ json: String) {
        let line = json.hasSuffix("\n") ? json : json + "\n"
        onStdout?(Data(line.utf8))
    }
}
