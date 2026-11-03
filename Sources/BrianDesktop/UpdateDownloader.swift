#if os(macOS)
import BrianClient
import Foundation

/// Downloads an https update and refuses a redirect that leaves https.
final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    // Set after super.init so the session can use this object as its delegate.
    private var session: URLSession!
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var progressHandler: ((Double) -> Void)?
    private var destination: URL?
    private var failure: Error?
    private var task: URLSessionDownloadTask?

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func download(from url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil, UpdateArchive.kind(for: url) != nil else {
            throw BrianClientError(message: "The download URL is not an https link to a .dmg or .zip.")
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lock.lock()
        self.destination = destination
        self.progressHandler = progress
        self.failure = nil
        lock.unlock()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.lock.lock()
            self.continuation = continuation
            self.lock.unlock()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            request.setValue("BrianDesktop", forHTTPHeaderField: "User-Agent")
            let task = self.session.downloadTask(with: request)
            self.lock.lock()
            self.task = task
            self.lock.unlock()
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > Int64(UpdateDownload.maximumBytes) ||
            (totalBytesExpectedToWrite > 0 && totalBytesExpectedToWrite > Int64(UpdateDownload.maximumBytes)) {
            lock.lock()
            failure = BrianClientError(message: "The update is larger than \(UpdateDownload.maximumBytes) bytes.")
            lock.unlock()
            downloadTask.cancel()
            return
        }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        let fraction = UpdateDownload.fraction(received: totalBytesWritten, expected: expected)
        lock.lock()
        let handler = progressHandler
        lock.unlock()
        handler?(fraction)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        let destination = self.destination
        lock.unlock()
        guard let destination else {
            lock.lock()
            failure = BrianClientError(message: "The download did not finish.")
            lock.unlock()
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.lock()
            failure = error
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url, url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
            lock.lock()
            failure = BrianClientError(message: "The download redirected away from https.")
            lock.unlock()
            completionHandler(nil)
            task.cancel()
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let failure = self.failure
        let destination = self.destination
        self.task = nil
        lock.unlock()
        if let failure {
            finish(.failure(failure))
            return
        }
        if let error {
            finish(.failure(error))
            return
        }
        if let status = (task.response as? HTTPURLResponse)?.statusCode, !(200...299).contains(status) {
            finish(.failure(BrianClientError(message: "The download returned HTTP \(status).")))
            return
        }
        guard let destination, FileManager.default.fileExists(atPath: destination.path) else {
            finish(.failure(BrianClientError(message: "The download did not finish.")))
            return
        }
        finish(.success(()))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
#endif
