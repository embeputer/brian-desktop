import CoreFoundation
import Foundation

enum JSONLookup {
    static func object(from data: Data) -> [String: Any]? {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return object(value)
    }

    static func object(_ value: Any?) -> [String: Any]? {
        guard let value else { return nil }
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let dictionary = value as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for key in dictionary.allKeys {
            guard let stringKey = key as? String else { continue }
            result[stringKey] = dictionary[stringKey]
        }
        return result
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber, !isBoolean(value) { return value.intValue }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber, isBoolean(value) { return value.boolValue }
        return nil
    }

    static func array(from data: Data) -> [Any]? {
        array(jsonValue(from: data))
    }

    static func array(_ value: Any?) -> [Any]? {
        if let value = value as? [Any] { return value }
        if let value = value as? NSArray { return value.map { $0 } }
        return nil
    }

    static func strings(_ value: Any?) -> [String] {
        array(value)?.compactMap { $0 as? String } ?? []
    }

    static func jsonValue(from data: Data) -> Any? {
        try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
