import Foundation

/// A client of one local `brian --mode rpc` process.
///
/// There is no handshake. The child reads JSON commands on stdin and writes
/// JSON responses and session events on stdout, one record per LF-terminated line.
/// Closing stdin asks Brian to shut down.
public final class BrianSession {
    public private(set) var snapshot: SessionSnapshot
    public var onChange: ((SessionSnapshot) -> Void)?

    private let configuration: BrianLaunchConfiguration
    private let transport: RpcTransport
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var reducer: RpcReducer
    private var framer = JsonlFramer()
    private var requestNumber = 0
    private var started = false
    private var stopped = false

    public convenience init(configuration: BrianLaunchConfiguration) {
        self.init(configuration: configuration, transport: ProcessRpcTransport(configuration: configuration))
    }

    deinit {
        stop()
    }

    init(configuration: BrianLaunchConfiguration, transport: RpcTransport) {
        self.configuration = configuration
        self.transport = transport
        let reducer = RpcReducer()
        self.reducer = reducer
        self.snapshot = reducer.snapshot
        transport.onStdout = { [weak self] data in
            self?.ingestStdout(data)
        }
        transport.onStderr = { [weak self] data in
            self?.ingestStderr(data)
        }
        transport.onExit = { [weak self] code in
            self?.ingestExit(code)
        }
    }

    public func start() throws {
        try mutateStart()
        do {
            try transport.start()
        } catch {
            mutate { $0.noteFailure(error.localizedDescription) }
            throw error
        }
        do {
            try write(type: "get_state", fields: [:])
        } catch {
            mutate { $0.noteFailure(error.localizedDescription) }
            throw error
        }
    }

    public func sendPrompt(_ text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let running = lock.sync { started && !stopped }
        guard running else {
            throw BrianClientError(message: "Not connected to brian.")
        }
        mutate { $0.noteOutgoingPrompt(trimmed) }
        do {
            try write(type: "prompt", fields: ["message": trimmed])
        } catch {
            mutate { $0.noteSendFailure(error.localizedDescription) }
            throw error
        }
    }

    public func abort() throws {
        try write(type: "abort", fields: [:])
    }

    /// Close stdin, then signal the child if it is still running.
    public func stop() {
        let shouldStop = lock.sync { () -> Bool in
            if stopped { return false }
            stopped = true
            return true
        }
        guard shouldStop else { return }
        transport.closeInput()
        transport.terminate()
    }

    private func mutateStart() throws {
        try lock.sync {
            if started {
                throw BrianClientError(message: "brian is already running.")
            }
            started = true
        }
        mutate { $0.noteLaunching(executablePath: configuration.executableURL.path) }
    }

    private func write(type: String, fields: [String: Any]) throws {
        let id = lock.sync { () -> String in
            requestNumber += 1
            return "req_\(requestNumber)"
        }
        var object: [String: Any] = ["id": id, "type": type]
        for (key, value) in fields {
            object[key] = value
        }
        try writeRaw(RpcWire.line(object))
    }

    private func writeRaw(_ data: Data) throws {
        try writeLock.sync {
            try transport.write(data)
        }
    }

    private func writeExtensionCancel(id: String) {
        let object: [String: Any] = [
            "cancelled": true,
            "id": id,
            "type": "extension_ui_response",
        ]
        guard let data = try? RpcWire.line(object) else { return }
        try? writeRaw(data)
    }

    private func ingestStdout(_ data: Data) {
        let lines = lock.sync { () -> [Data] in
            if data.isEmpty {
                return framer.finish()
            }
            return framer.append(data)
        }
        consume(lines)
    }

    private func ingestStderr(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
        mutate { $0.noteStderr(text) }
    }

    private func ingestExit(_ code: Int32) {
        let leftover = lock.sync { framer.finish() }
        consume(leftover)
        mutate { $0.noteExit(code: code) }
    }

    private func consume(_ lines: [Data]) {
        var cancellations: [String] = []
        mutate { reducer in
            for line in lines {
                for effect in reducer.apply(line) {
                    switch effect {
                    case .cancelExtensionUI(let id):
                        cancellations.append(id)
                    }
                }
            }
        }
        for id in cancellations {
            writeExtensionCancel(id: id)
        }
    }

    private func mutate(_ body: (inout RpcReducer) -> Void) {
        let updated = lock.sync { () -> SessionSnapshot in
            body(&reducer)
            snapshot = reducer.snapshot
            return snapshot
        }
        onChange?(updated)
    }
}

private extension NSLock {
    func sync<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
