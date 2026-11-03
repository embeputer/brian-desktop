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

public struct SessionSnapshot: Equatable, Sendable {
    public var phase: SessionPhase
    public var messages: [ChatMessage]
    public var statusLine: String
    public var stderr: String
    public var modelLabel: String?
    public var sessionID: String?

    public init(
        phase: SessionPhase,
        messages: [ChatMessage],
        statusLine: String,
        stderr: String,
        modelLabel: String?,
        sessionID: String?
    ) {
        self.phase = phase
        self.messages = messages
        self.statusLine = statusLine
        self.stderr = stderr
        self.modelLabel = modelLabel
        self.sessionID = sessionID
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
