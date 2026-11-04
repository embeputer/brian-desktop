import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ServeTask: AnyObject {
    func cancel()
}

public protocol ServeTransport: AnyObject {
    func send(request: URLRequest, completion: @escaping (Result<(Int, Data), Error>) -> Void) -> ServeTask
}

public final class URLSessionServeTransport: ServeTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(request: URLRequest, completion: @escaping (Result<(Int, Data), Error>) -> Void) -> ServeTask {
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(.success((status, data ?? Data())))
        }
        task.resume()
        return URLSessionTaskBox(task: task)
    }
}

private final class URLSessionTaskBox: ServeTask {
    private let task: URLSessionTask

    init(task: URLSessionTask) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

/// Client for `brian serve`.
///
/// The server returns one JSON body, `{ "text" }`, after the turn finishes.
/// This does not speak RPC and does not invent a token stream.
public final class ServeSession {
    public private(set) var snapshot: SessionSnapshot
    public var onChange: ((SessionSnapshot) -> Void)?

    private let endpoint: ServeEndpoint
    private let transport: ServeTransport
    private let lock = NSLock()
    private var reducer = RpcReducer()
    private var activeTask: ServeTask?
    private var statusTask: ServeTask?
    private var stopped = false

    public init(endpoint: ServeEndpoint, transport: ServeTransport = URLSessionServeTransport()) {
        self.endpoint = endpoint
        self.transport = transport
        snapshot = reducer.snapshot
    }

    public func connect() {
        mutate { reducer in
            reducer.noteLaunching(executablePath: endpoint.baseURL.absoluteString)
            reducer.noteStatusLine("Connecting to \(endpoint.baseURL.absoluteString)")
        }
        var request = URLRequest(url: endpoint.url(path: "/v1/health"))
        request.httpMethod = "GET"
        send(request) { [weak self] result in
            self?.applyHealth(result)
        }
    }

    public func fetchStatus() {
        guard !lock.sync(operation: { stopped }) else { return }
        var request = URLRequest(url: endpoint.url(path: "/v1/status"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        let task = transport.send(request: request) { [weak self] result in
            self?.applyStatus(result)
        }
        lock.lock()
        statusTask = task
        lock.unlock()
    }

    public func sendPrompt(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !lock.sync(operation: { stopped }) else { return }
        mutate { $0.noteOutgoingPrompt(trimmed) }
        mutate { $0.noteStatusLine("Waiting for a reply…") }
        var request = URLRequest(url: endpoint.url(path: "/v1/prompt"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["prompt": trimmed])
        send(request) { [weak self] result in
            self?.applyPrompt(result)
        }
    }

    public func cancelPrompt() {
        lock.lock()
        let task = activeTask
        lock.unlock()
        task?.cancel()
    }

    public func stop() {
        lock.lock()
        stopped = true
        let task = activeTask
        let status = statusTask
        lock.unlock()
        task?.cancel()
        status?.cancel()
    }

    private func send(_ request: URLRequest, completion: @escaping (Result<(Int, Data), Error>) -> Void) {
        let task = transport.send(request: request, completion: completion)
        lock.lock()
        activeTask = task
        lock.unlock()
    }

    private func applyHealth(_ result: Result<(Int, Data), Error>) {
        if isCancellation(result) || lock.sync(operation: { stopped }) { return }
        switch result {
        case .failure(let error):
            mutate { $0.noteFailure("Couldn't reach brian serve. \(error.localizedDescription)") }
        case .success(let (status, data)):
            guard status == 200, let object = JSONLookup.object(from: data), JSONLookup.bool(object["ok"]) == true else {
                mutate { $0.noteFailure(serveError(status: status, data: data, fallback: "brian serve did not answer /v1/health.")) }
                return
            }
            let name = JSONLookup.string(object["name"]) ?? "brian"
            let version = JSONLookup.string(object["version"]) ?? ""
            let label = [name, version].filter { !$0.isEmpty }.joined(separator: " ")
            mutate { $0.noteConnected(label: label) }
        }
    }

    private func applyStatus(_ result: Result<(Int, Data), Error>) {
        if isCancellation(result) || lock.sync(operation: { stopped }) { return }
        switch result {
        case .failure(let error):
            mutate { $0.noteRemoteSummary("Couldn't read serve status. \(error.localizedDescription)") }
        case .success(let (status, data)):
            if status == 200, let summary = ServeStatusSummary.parse(data) {
                mutate { $0.noteRemoteSummary(summary.line) }
                return
            }
            let fallback = status == 401 ? "The access token was rejected." : "brian serve did not return /v1/status."
            mutate { $0.noteRemoteSummary(serveError(status: status, data: data, fallback: fallback)) }
        }
    }

    private func applyPrompt(_ result: Result<(Int, Data), Error>) {
        if isCancellation(result) {
            mutate { reducer in
                reducer.noteSendFailure("Stopped.")
                reducer.noteStatusLine("Stopped")
            }
            return
        }
        switch result {
        case .failure(let error):
            mutate { $0.noteSendFailure(error.localizedDescription) }
        case .success(let (status, data)):
            let object = JSONLookup.object(from: data)
            if status == 200, let text = object.flatMap({ JSONLookup.string($0["text"]) }) {
                mutate { $0.noteAssistantReply(text) }
                return
            }
            let fallback = status == 401 ? "The access token was rejected." : "brian serve rejected the prompt."
            mutate { $0.noteSendFailure(serveError(status: status, data: data, fallback: fallback)) }
        }
    }

    private func serveError(status: Int, data: Data, fallback: String) -> String {
        if let object = JSONLookup.object(from: data), let error = JSONLookup.string(object["error"]), !error.isEmpty {
            return error
        }
        if status == 0 { return fallback }
        return "\(fallback) (HTTP \(status))"
    }

    private func isCancellation(_ result: Result<(Int, Data), Error>) -> Bool {
        guard case .failure(let error) = result else { return false }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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
    func sync<T>(operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
