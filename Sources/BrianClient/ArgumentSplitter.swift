import Foundation

public enum ArgumentSplitter {
    /// Split a command tail on whitespace, keeping double-quoted sections intact.
    public static func split(_ input: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var inQuotes = false
        var isEscaped = false

        for character in input {
            if isEscaped {
                current.append(character)
                isEscaped = false
                continue
            }
            if character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character.isWhitespace, !inQuotes {
                if !current.isEmpty {
                    arguments.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty {
            arguments.append(current)
        }
        return arguments
    }
}
