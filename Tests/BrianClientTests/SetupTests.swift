@testable import BrianClient
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest

final class SetupTests: XCTestCase {
    func testDefaultWindowIsSlightlyTransparentUntilMadeSolid() {
        XCTAssertEqual(AppearancePreference.opacity(solid: false, transparency: AppearancePreference.defaultTransparency), 0.9, accuracy: 0.0001)
        XCTAssertEqual(AppearancePreference.opacity(solid: true, transparency: 0.4), 1)
        XCTAssertEqual(
            AppearancePreference.opacity(solid: false, transparency: 2),
            1 - AppearancePreference.maximumTransparency,
            accuracy: 0.0001
        )
    }

    func testBlurSliderClampsAndStaysOffWhenSolid() {
        XCTAssertEqual(AppearancePreference.blurAmount(-0.2), 0, accuracy: 0.0001)
        XCTAssertEqual(AppearancePreference.blurAmount(3), AppearancePreference.maximumBlur, accuracy: 0.0001)
        XCTAssertEqual(AppearancePreference.appliedBlur(solid: false, blur: AppearancePreference.defaultBlur), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AppearancePreference.appliedBlur(solid: true, blur: 0.8), 0, accuracy: 0.0001)
    }

    func testParsesHostPortAndURL() throws {
        let hostPort = try XCTUnwrap(endpoint("brian.example:9000", token: "tok"))
        XCTAssertEqual(hostPort.baseURL.absoluteString, "https://brian.example:9000")
        XCTAssertEqual(hostPort.token, "tok")

        let bareHost = try XCTUnwrap(endpoint("brian.example", token: "tok"))
        XCTAssertEqual(bareHost.baseURL.absoluteString, "https://brian.example")

        let local = try XCTUnwrap(endpoint("localhost", token: "tok"))
        XCTAssertEqual(local.baseURL.absoluteString, "http://localhost:7333")

        let https = try XCTUnwrap(endpoint("https://brian.example/v1/prompt", token: " tok "))
        XCTAssertEqual(https.baseURL.absoluteString, "https://brian.example")
        XCTAssertEqual(https.token, "tok")
        XCTAssertEqual(https.url(path: "/v1/health").absoluteString, "https://brian.example/v1/health")

        let explicitHTTP = try XCTUnwrap(endpoint("http://127.0.0.1:80", token: "tok"))
        XCTAssertEqual(explicitHTTP.baseURL.absoluteString, "http://127.0.0.1:80")

        XCTAssertNil(endpoint("  ", token: "tok"))
        XCTAssertNil(endpoint("brian.example:7333", token: " "))
    }

    func testRemoteHostsNeverGetPlainHTTP() throws {
        for address in ["brian.example", "brian.example:7333", "10.1.2.3:7333", "devbox", "127.evil.example:7333", "[fe80::1]:7333"] {
            let parsed = try XCTUnwrap(endpoint(address, token: "tok"), address)
            XCTAssertEqual(parsed.baseURL.scheme, "https", address)
            XCTAssertTrue(parsed.protectsToken, address)
        }
        for address in ["http://brian.example", "http://10.1.2.3:7333", "HTTP://brian.example:7333", "http://127.0.0.1.evil.example", "http://localhost.evil.example"] {
            guard case .failure(let error) = ServeAddress.parse(address: address, token: "tok") else {
                XCTFail("\(address) should be refused")
                continue
            }
            XCTAssertTrue(error.message.contains("plain http"), address)
        }
    }

    func testLoopbackHostsKeepPlainHTTP() throws {
        for address in ["localhost", "LOCALHOST:9000", "127.0.0.1", "127.1.2.3:7333", "[::1]", "http://localhost:7333", "http://[::1]:7333"] {
            let parsed = try XCTUnwrap(endpoint(address, token: "tok"), address)
            XCTAssertEqual(parsed.baseURL.scheme, "http", address)
            XCTAssertTrue(parsed.protectsToken, address)
        }
        XCTAssertEqual(try XCTUnwrap(endpoint("[::1]", token: "tok")).baseURL.port, 7333)
        XCTAssertFalse(ServeAddress.isLoopback(host: "127.0.0.256"))
        XCTAssertFalse(ServeAddress.isLoopback(host: "127.0.0"))
        XCTAssertFalse(ServeAddress.isLoopback(host: "localhost.evil.example"))
    }

    func testBareRemoteHostNeverSendsTokenOverHTTP() throws {
        for address in ["brian.example", "brian.example:7333", "10.1.2.3:7333"] {
            let transport = ScriptedServeTransport()
            transport.results = [
                .success((200, Data(#"{"ok":true,"name":"brian","version":"9"}"#.utf8))),
                .success((200, Data(#"{"routines":0,"beeperConnected":false,"pendingDrafts":0}"#.utf8))),
                .success((200, Data(#"{"text":"ok"}"#.utf8))),
            ]
            let session = ServeSession(endpoint: try XCTUnwrap(endpoint(address, token: "secret")), transport: transport)
            session.connect()
            session.fetchStatus()
            session.sendPrompt("hello")
            XCTAssertEqual(transport.requests.count, 3, address)
            for request in transport.requests where request.value(forHTTPHeaderField: "Authorization") != nil {
                XCTAssertEqual(request.url?.scheme, "https", address)
            }
        }
    }

    func testServeSessionRefusesCleartextRemoteEndpoint() throws {
        let transport = ScriptedServeTransport()
        let insecure = ServeEndpoint(baseURL: try XCTUnwrap(URL(string: "http://brian.example:7333")), token: "secret")
        XCTAssertFalse(insecure.protectsToken)
        let session = ServeSession(endpoint: insecure, transport: transport)
        session.connect()
        session.fetchStatus()
        session.sendPrompt("hello")
        XCTAssertTrue(transport.requests.isEmpty)
        guard case .failed(let message) = session.snapshot.phase else {
            return XCTFail("expected a failed phase, got \(session.snapshot.phase)")
        }
        XCTAssertTrue(message.contains("plain http"))
        XCTAssertFalse(session.snapshot.messages.contains { $0.role == .user })
    }

    func testWelcomeShowsOnceBeforeSetup() throws {
        XCTAssertEqual(FirstLaunch.step(welcomeSeen: false, hasSavedConnection: false, choosingConnection: false), .welcome)
        XCTAssertEqual(FirstLaunch.step(welcomeSeen: true, hasSavedConnection: false, choosingConnection: false), .setup)
        XCTAssertEqual(FirstLaunch.step(welcomeSeen: false, hasSavedConnection: true, choosingConnection: false), .ready)
        XCTAssertEqual(FirstLaunch.step(welcomeSeen: true, hasSavedConnection: true, choosingConnection: true), .setup)

        let name = "dev.brian.desktop.welcome.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let store = ConnectionSettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasSeenWelcome())
        store.markWelcomeSeen()
        XCTAssertTrue(store.hasSeenWelcome())
        XCTAssertNil(store.load())
        defaults.removePersistentDomain(forName: name)
    }

    func testSettingsRoundTripAndLegacyPath() throws {
        let name = "dev.brian.desktop.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let store = ConnectionSettingsStore(defaults: defaults)
        XCTAssertNil(store.load())

        defaults.set("/usr/local/bin/brian", forKey: ConnectionSettings.legacyExecutableKey)
        let legacy = try XCTUnwrap(store.load())
        XCTAssertEqual(legacy.mode, .local)
        XCTAssertEqual(legacy.executablePath, "/usr/local/bin/brian")

        let remote = ConnectionSettings(
            mode: .remote,
            executablePath: "",
            remoteAddress: "http://brian.example:7333",
            remoteToken: "secret"
        )
        store.save(remote)
        XCTAssertEqual(store.load(), remote)
        defaults.removePersistentDomain(forName: name)
    }

    func testServeSessionUsesFinishedJSONBody() throws {
        let transport = ScriptedServeTransport()
        transport.results = [
            .success((200, Data(#"{"ok":true,"name":"brian","version":"9"}"#.utf8))),
            .success((200, Data(#"{"text":"full reply"}"#.utf8))),
        ]
        let endpoint = try XCTUnwrap(endpoint("brian.example:7333", token: "secret"))
        let session = ServeSession(endpoint: endpoint, transport: transport)
        session.connect()
        XCTAssertEqual(session.snapshot.phase, .ready)
        XCTAssertEqual(session.snapshot.modelLabel, "brian 9")
        XCTAssertEqual(transport.requests.first?.url?.path, "/v1/health")

        session.sendPrompt("hello")
        let prompt = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(prompt.url?.path, "/v1/prompt")
        XCTAssertEqual(prompt.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        let body = try XCTUnwrap(prompt.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["prompt"], "hello")

        let assistant = try XCTUnwrap(session.snapshot.messages.last { $0.role == .assistant })
        XCTAssertEqual(assistant.text, "full reply")
        XCTAssertTrue(assistant.isComplete)
        XCTAssertNil(assistant.deliveryJSON)
        XCTAssertEqual(session.snapshot.phase, .ready)
        XCTAssertEqual(session.snapshot.messages.filter { $0.role == .assistant }.count, 1)
    }

    func testServeSessionSurfacesRejectedToken() throws {
        let transport = ScriptedServeTransport()
        transport.results = [
            .success((200, Data(#"{"ok":true,"name":"brian","version":"9"}"#.utf8))),
            .success((401, Data(#"{"error":"unauthorized"}"#.utf8))),
        ]
        let endpoint = try XCTUnwrap(endpoint("https://brian.example:7333", token: "nope"))
        let session = ServeSession(endpoint: endpoint, transport: transport)
        session.connect()
        session.sendPrompt("hello")
        XCTAssertEqual(session.snapshot.phase, .ready)
        XCTAssertTrue(session.snapshot.messages.contains { $0.role == .status && $0.text == "unauthorized" })
    }

    func testInstallRunsOnlyWhenBrianIsMissing() throws {
        let runner = RecordingRunner()
        let present = URL(fileURLWithPath: "/tmp/brian")
        let found = try LocalBrianSetup.resolveOrInstall(
            explicitPath: nil,
            environment: ["PATH": "/tmp", "HOME": "/nowhere"],
            runner: runner,
            locateBrian: { present },
            locateNpm: { nil }
        )
        XCTAssertEqual(found, present)
        XCTAssertTrue(runner.calls.isEmpty)

        runner.prefix = "/opt/brian"
        let installed = try LocalBrianSetup.resolveOrInstall(
            explicitPath: nil,
            environment: ["PATH": "/tmp", "HOME": "/nowhere"],
            runner: runner,
            locateBrian: { nil },
            locateNpm: { URL(fileURLWithPath: "/usr/bin/npm") },
            isExecutable: { $0 == "/opt/brian/bin/brian" }
        )
        XCTAssertEqual(installed.path, "/opt/brian/bin/brian")
        XCTAssertEqual(runner.calls.map(\.arguments), [
            LocalBrianSetup.installArguments,
            ["prefix", "-g"],
        ])

        let missing = URL(fileURLWithPath: "/no/such/brian-\(UUID().uuidString)")
        XCTAssertThrowsError(
            try LocalBrianSetup.resolveOrInstall(
                explicitPath: missing.path,
                environment: ["PATH": "/tmp", "HOME": "/nowhere"],
                runner: runner
            )
        )
    }

    func testServeProcessReturnsWholeReply() throws {
        let node = try nodeExecutable()
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-serve.mjs")
        let process = Process()
        process.executableURL = node
        process.arguments = [fixture.path]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        defer { process.terminate() }

        let portData = output.fileHandleForReading.availableData
        let port = try XCTUnwrap(Int(String(data: portData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""))
        let endpoint = try XCTUnwrap(endpoint("127.0.0.1:\(port)", token: "secret-token"))
        let session = ServeSession(endpoint: endpoint)
        defer { session.stop() }
        session.connect()
        waitUntil {
            switch session.snapshot.phase {
            case .ready, .failed:
                return true
            case .idle, .launching, .streaming, .exited:
                return false
            }
        }
        if case .failed(let message) = session.snapshot.phase {
            XCTFail(message)
        }
        XCTAssertEqual(session.snapshot.modelLabel, "brian 9")
        session.sendPrompt("hello")
        waitUntil { session.snapshot.messages.contains { $0.role == .assistant && $0.text == "echo:hello" } }
        XCTAssertEqual(session.snapshot.messages.last { $0.role == .assistant }?.text, "echo:hello")
        XCTAssertEqual(session.snapshot.phase, .ready)
    }

    private func endpoint(_ address: String, token: String) -> ServeEndpoint? {
        if case .success(let endpoint) = ServeAddress.parse(address: address, token: token) {
            return endpoint
        }
        return nil
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
}

private final class ScriptedServeTransport: ServeTransport {
    var requests: [URLRequest] = []
    var results: [Result<(Int, Data), Error>] = []

    func send(request: URLRequest, completion: @escaping (Result<(Int, Data), Error>) -> Void) -> ServeTask {
        requests.append(request)
        completion(results.removeFirst())
        return NoopServeTask()
    }
}

private final class NoopServeTask: ServeTask {
    func cancel() {}
}

private final class RecordingRunner: CommandRunning {
    var prefix = "/opt/brian"
    var calls: [(executable: URL, arguments: [String])] = []

    func run(executable: URL, arguments: [String], environment: [String: String]) throws -> CommandOutput {
        calls.append((executable, arguments))
        if arguments == ["prefix", "-g"] {
            return CommandOutput(status: 0, stdout: prefix + "\n", stderr: "")
        }
        return CommandOutput(status: 0, stdout: "", stderr: "")
    }
}
