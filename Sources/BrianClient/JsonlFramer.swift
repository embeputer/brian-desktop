import Foundation

/// Splits a byte stream into JSONL records.
///
/// Brian's RPC mode frames records with LF only. A carriage return before that
/// LF is stripped. Unicode line and paragraph separators stay inside the record.
struct JsonlFramer {
    private var buffer = Data()

    mutating func append(_ data: Data) -> [Data] {
        guard !data.isEmpty else { return [] }
        buffer.append(data)
        return drain(flushRemainder: false)
    }

    mutating func finish() -> [Data] {
        drain(flushRemainder: true)
    }

    private mutating func drain(flushRemainder: Bool) -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if line.last == 0x0D {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }
        if flushRemainder, !buffer.isEmpty {
            var line = buffer
            buffer.removeAll(keepingCapacity: true)
            if line.last == 0x0D {
                line.removeLast()
            }
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

enum RpcWire {
    static func line(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw BrianClientError(message: "Could not encode an RPC command.")
        }
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }
}
