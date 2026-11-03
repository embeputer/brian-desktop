import Foundation

public struct ServeEndpoint: Equatable, Sendable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    public func url(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        components.scheme = baseURL.scheme
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url ?? baseURL
    }
}

/// Parses the address a person types for `brian serve`.
///
/// `host`, `host:port`, and `http(s)://host:port` are accepted. A missing port on
/// plain http uses 7333, which is serve's default. https without a port stays on 443.
public enum ServeAddress {
    public static func parse(address: String, token: String) -> Result<ServeEndpoint, BrianClientError> {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddress.isEmpty {
            return .failure(BrianClientError(message: "Enter the host and port, or a URL."))
        }
        if trimmedToken.isEmpty {
            return .failure(BrianClientError(message: "Enter the access token from serve.json."))
        }

        let withScheme = trimmedAddress.contains("://") ? trimmedAddress : "http://\(trimmedAddress)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme,
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            return .failure(BrianClientError(message: "That address is not a host:port or an http(s) URL."))
        }
        if scheme == "http", components.port == nil {
            components.port = 7333
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let baseURL = components.url else {
            return .failure(BrianClientError(message: "That address is not a host:port or an http(s) URL."))
        }
        return .success(ServeEndpoint(baseURL: baseURL, token: trimmedToken))
    }
}
