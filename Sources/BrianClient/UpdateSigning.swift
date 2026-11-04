import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif canImport(Crypto)
import Crypto
#endif

/// Ed25519 check on each appcast item. The release job signs `message(version:build:sha256:)` with the private key in
/// the `BRIAN_UPDATE_SIGNING_KEY` Actions secret. The app only carries the public key, so an item edited by anyone
/// without that key, or a disk image that does not hash to the signed SHA-256, is never installed.
public enum UpdateSigning {
    /// Raw 32-byte Ed25519 public key, base64. `Scripts/write-appcast.py` refuses to publish a release signed with
    /// any other key.
    public static let publicKey = ""

    public static func message(version: String, build: String, sha256: String) -> Data {
        Data("dev.brian.desktop update\nversion=\(version)\nbuild=\(build)\nsha256=\(sha256.lowercased())\n".utf8)
    }

    public static func isSigned(_ item: ReleaseFeedItem, publicKey: String = publicKey) -> Bool {
        (try? verifySignature(of: item, publicKey: publicKey)) != nil
    }

    public static func verifySignature(of item: ReleaseFeedItem, publicKey: String = publicKey) throws {
        #if canImport(CryptoKit) || canImport(Crypto)
        guard let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            throw BrianClientError(message: "This build of Brian has no update signing key.")
        }
        guard isSHA256(item.sha256),
              let signature = Data(base64Encoded: item.signature), signature.count == 64,
              key.isValidSignature(signature, for: message(version: item.version, build: item.build, sha256: item.sha256))
        else {
            throw BrianClientError(message: "The update is not signed with Brian's release key.")
        }
        #else
        throw BrianClientError(message: "This system cannot check update signatures.")
        #endif
    }

    /// Checks the signature, then that the downloaded file is the one that was signed. Only a `VerifiedArchive` can
    /// be extracted and staged.
    public static func verifyArchive(at archive: URL, item: ReleaseFeedItem, publicKey: String = publicKey) throws -> VerifiedArchive {
        try verifySignature(of: item, publicKey: publicKey)
        guard try sha256Hex(of: archive) == item.sha256.lowercased() else {
            throw BrianClientError(message: "The download does not match the signed release.")
        }
        return VerifiedArchive(url: archive, item: item)
    }

    static func isSHA256(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) ||
                (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte) ||
                (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
        }
    }

    static func sha256Hex(of file: URL) throws -> String {
        #if canImport(CryptoKit) || canImport(Crypto)
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var total = 0
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            total += chunk.count
            guard total <= UpdateDownload.maximumBytes else {
                throw BrianClientError(message: "The update is larger than \(UpdateDownload.maximumBytes) bytes.")
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        throw BrianClientError(message: "This system cannot check update signatures.")
        #endif
    }
}

/// A downloaded archive whose SHA-256 matches a signed feed item.
public struct VerifiedArchive: Equatable, Sendable {
    public let url: URL
    public let item: ReleaseFeedItem

    init(url: URL, item: ReleaseFeedItem) {
        self.url = url
        self.item = item
    }
}
