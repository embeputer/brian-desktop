import Foundation

public enum ChatRole: String, Equatable, Sendable {
    case user
    case assistant
    case status
}

/// One plain transcript row.
///
/// `deliveryJSON` keeps Brian's platform-neutral delivery envelope (text, embeds,
/// questions, attachments) for a later surface. This window renders `text` only.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var role: ChatRole
    public var text: String
    public var deliveryJSON: String?
    public var isComplete: Bool

    public init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        deliveryJSON: String? = nil,
        isComplete: Bool = true
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.deliveryJSON = deliveryJSON
        self.isComplete = isComplete
    }
}

public enum SessionPhase: Equatable, Sendable {
    case idle
    case launching
    case ready
    case streaming
    case failed(String)
    case exited(Int32)

    public var canSend: Bool {
        switch self {
        case .ready:
            return true
        case .idle, .launching, .streaming, .failed, .exited:
            return false
        }
    }
}

public struct SlashCommand: Equatable, Sendable, Identifiable {
    public var name: String
    public var detail: String
    public var source: String

    public var id: String { name }

    public init(name: String, detail: String, source: String) {
        self.name = name
        self.detail = detail
        self.source = source
    }
}

public struct ModelChoice: Equatable, Sendable, Identifiable {
    public var provider: String
    public var modelID: String
    public var name: String
    public var reasoning: Bool

    public var id: String { "\(provider)/\(modelID)" }

    public init(provider: String, modelID: String, name: String, reasoning: Bool) {
        self.provider = provider
        self.modelID = modelID
        self.name = name
        self.reasoning = reasoning
    }
}

public struct ForkPoint: Equatable, Sendable, Identifiable {
    public var entryID: String
    public var text: String

    public var id: String { entryID }

    public init(entryID: String, text: String) {
        self.entryID = entryID
        self.text = text
    }
}

public struct SessionSnapshot: Equatable, Sendable {
    public var phase: SessionPhase
    public var messages: [ChatMessage]
    public var statusLine: String
    public var stderr: String
    public var modelLabel: String?
    public var sessionID: String?
    public var sessionName: String?
    public var sessionFile: String?
    public var thinkingLevel: String?
    public var commands: [SlashCommand]
    public var models: [ModelChoice]
    public var thinkingLevels: [String]
    public var forkPoints: [ForkPoint]
    public var remoteSummary: String?

    public init(
        phase: SessionPhase,
        messages: [ChatMessage],
        statusLine: String,
        stderr: String,
        modelLabel: String?,
        sessionID: String?,
        sessionName: String? = nil,
        sessionFile: String? = nil,
        thinkingLevel: String? = nil,
        commands: [SlashCommand] = [],
        models: [ModelChoice] = [],
        thinkingLevels: [String] = [],
        forkPoints: [ForkPoint] = [],
        remoteSummary: String? = nil
    ) {
        self.phase = phase
        self.messages = messages
        self.statusLine = statusLine
        self.stderr = stderr
        self.modelLabel = modelLabel
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.sessionFile = sessionFile
        self.thinkingLevel = thinkingLevel
        self.commands = commands
        self.models = models
        self.thinkingLevels = thinkingLevels
        self.forkPoints = forkPoints
        self.remoteSummary = remoteSummary
    }

    public static let disconnected = SessionSnapshot(
        phase: .idle,
        messages: [],
        statusLine: "Not connected",
        stderr: "",
        modelLabel: nil,
        sessionID: nil
    )

    public var canSend: Bool { phase.canSend }
}

public struct BrianClientError: LocalizedError, Equatable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
