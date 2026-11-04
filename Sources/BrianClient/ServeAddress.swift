import Foundation

public struct ServeEndpoint: Equatable, Sendable {
    public var baseURL: URL
    public var token: String

    public init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// The bearer token may only travel over https, or over http to this machine.
    public var protectsToken: Bool {
        switch baseURL.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return ServeAddress.isLoopback(host: baseURL.host ?? "")
        default:
            return false
        }
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
/// `host`, `host:port`, and `http(s)://host:port` are accepted. Without a scheme,
/// a loopback host uses http and any other host uses https, because the bearer
/// token must not cross the network in cleartext. Plain http is refused for any
/// host that is not loopback. A missing port on http uses 7333, which is serve's
/// default. https without a port stays on 443.
public enum ServeAddress {
    static let cleartextRemoteMessage = "The access token can't be sent over plain http to another machine. Use an https URL (a TLS proxy in front of brian serve), or an SSH tunnel to localhost."

    public static func parse(address: String, token: String) -> Result<ServeEndpoint, BrianClientError> {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAddress.isEmpty {
            return .failure(BrianClientError(message: "Enter the host and port, or a URL."))
        }
        if trimmedToken.isEmpty {
            return .failure(BrianClientError(message: "Enter the access token from serve.json."))
        }

        let hasScheme = trimmedAddress.contains("://")
        let withScheme = hasScheme ? trimmedAddress : "http://\(trimmedAddress)"
        guard var components = URLComponents(string: withScheme),
              let parsedScheme = components.scheme?.lowercased(),
              parsedScheme == "http" || parsedScheme == "https",
              let host = components.host,
              !host.isEmpty
        else {
            return .failure(BrianClientError(message: "That address is not a host:port or an http(s) URL."))
        }
        let loopback = isLoopback(host: host)
        let scheme = hasScheme ? parsedScheme : (loopback ? "http" : "https")
        if scheme == "http", !loopback {
            return .failure(BrianClientError(message: cleartextRemoteMessage))
        }
        components.scheme = scheme
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

    /// `localhost`, `127.0.0.0/8`, and `::1`. Names that merely start with `127.` do not count.
    public static func isLoopback(host: String) -> Bool {
        var name = host.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") {
            name = String(name.dropFirst().dropLast())
        }
        if name.hasSuffix(".") {
            name = String(name.dropLast())
        }
        if name == "localhost" || name == "::1" || name == "0:0:0:0:0:0:0:1" {
            return true
        }
        let octets = name.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        let values = octets.compactMap { octet -> Int? in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isASCII), octet.allSatisfy(\.isNumber) else { return nil }
            return Int(octet).flatMap { $0 <= 255 ? $0 : nil }
        }
        return values.count == 4 && values[0] == 127
    }
}
