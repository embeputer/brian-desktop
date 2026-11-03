import Foundation

enum RpcEffect: Equatable {
    case cancelExtensionUI(id: String)
}

/// Turns Brian RPC stdout records into a plain transcript.
struct RpcReducer {
    private(set) var snapshot: SessionSnapshot
    private var textBlocks: [Int: String] = [:]
    private var openAssistantID: UUID?
    private var awaitingSettle = false
    private var didExit = false
    private let stderrLimit = 8_000

    init(snapshot: SessionSnapshot = .disconnected) {
        self.snapshot = snapshot
    }

    mutating func noteStatusLine(_ line: String) {
        snapshot.statusLine = line
    }

    mutating func noteConnected(label: String) {
        snapshot.modelLabel = label
        snapshot.phase = .ready
        snapshot.statusLine = "Connected · \(label)"
    }

    mutating func noteAssistantReply(_ text: String) {
        snapshot.messages.append(ChatMessage(role: .assistant, text: text))
        awaitingSettle = false
        guard !didExit else { return }
        snapshot.phase = .ready
        snapshot.statusLine = connectedStatus()
    }

    mutating func noteLaunching(executablePath: String) {
        snapshot.phase = .launching
        snapshot.statusLine = "Starting \(executablePath)"
    }

    mutating func noteFailure(_ message: String) {
        snapshot.phase = .failed(message)
        snapshot.statusLine = message
    }

    mutating func noteStderr(_ text: String) {
        guard !text.isEmpty else { return }
        snapshot.stderr.append(text)
        if snapshot.stderr.count > stderrLimit {
            snapshot.stderr = String(snapshot.stderr.suffix(stderrLimit))
        }
    }

    mutating func noteOutgoingPrompt(_ text: String) {
        snapshot.messages.append(ChatMessage(role: .user, text: text))
        snapshot.phase = .streaming
        snapshot.statusLine = "Sending…"
        textBlocks = [:]
        openAssistantID = nil
        awaitingSettle = true
    }

    mutating func noteSendFailure(_ message: String) {
        appendStatus(message)
        awaitingSettle = false
        if !didExit {
            snapshot.phase = .ready
            snapshot.statusLine = connectedStatus()
        }
    }

    mutating func noteRemoteSummary(_ line: String?) {
        snapshot.remoteSummary = line
    }

    mutating func noteExit(code: Int32) {
        didExit = true
        closeOpenAssistant()
        snapshot.phase = .exited(code)
        snapshot.statusLine = code == 0 ? "brian exited" : "brian exited (\(code))"
    }

    mutating func apply(_ line: Data) -> [RpcEffect] {
        guard let object = JSONLookup.object(from: line) else {
            let preview = String(data: line.prefix(160), encoding: .utf8) ?? "binary"
            appendStatus("Ignored a non-JSON stdout record: \(preview)")
            return []
        }
        guard let type = JSONLookup.string(object["type"]) else {
            appendStatus("Ignored an RPC record with no type.")
            return []
        }
        switch recordKind(type) {
        case .response:
            applyResponse(object)
            return []
        case .messageStart:
            applyMessageStart(object)
            return []
        case .messageUpdate:
            applyMessageUpdate(object)
            return []
        case .messageEnd:
            applyMessageEnd(object)
            return []
        case .toolStart:
            let name = JSONLookup.string(object["toolName"]) ?? "tool"
            appendStatus("Running \(name)")
            return []
        case .toolEnd:
            if JSONLookup.bool(object["isError"]) == true {
                let name = JSONLookup.string(object["toolName"]) ?? "tool"
                appendStatus("\(name) failed")
            }
            return []
        case .agentEnd:
            if JSONLookup.bool(object["willRetry"]) == true {
                snapshot.statusLine = "Retrying…"
            }
            return []
        case .agentSettled:
            applySettled(aborted: JSONLookup.bool(object["aborted"]) == true)
            return []
        case .autoRetryStart:
            let attempt = JSONLookup.int(object["attempt"]) ?? 1
            snapshot.phase = .streaming
            snapshot.statusLine = "Retrying (attempt \(attempt))…"
            return []
        case .compactionStart:
            snapshot.statusLine = "Compacting…"
            return []
        case .extensionError:
            let message = JSONLookup.string(object["error"]) ?? "An extension failed."
            appendStatus(message)
            return []
        case .extensionUI:
            return applyExtensionUI(object)
        case .delivery:
            applyDelivery(object)
            return []
        case .other:
            return []
        }
    }

    private enum RecordKind {
        case response
        case messageStart
        case messageUpdate
        case messageEnd
        case toolStart
        case toolEnd
        case agentEnd
        case agentSettled
        case autoRetryStart
        case compactionStart
        case extensionError
        case extensionUI
        case delivery
        case other
    }

    private func recordKind(_ type: String) -> RecordKind {
        switch type {
        case "response":
            return .response
        case "message_start":
            return .messageStart
        case "message_update":
            return .messageUpdate
        case "message_end":
            return .messageEnd
        case "tool_execution_start":
            return .toolStart
        case "tool_execution_end":
            return .toolEnd
        case "agent_end":
            return .agentEnd
        case "agent_settled":
            return .agentSettled
        case "auto_retry_start":
            return .autoRetryStart
        case "compaction_start":
            return .compactionStart
        case "extension_error":
            return .extensionError
        case "extension_ui_request":
            return .extensionUI
        case "delivery":
            return .delivery
        default:
            return .other
        }
    }

    private mutating func applyResponse(_ object: [String: Any]) {
        let command = JSONLookup.string(object["command"]) ?? ""
        let success = JSONLookup.bool(object["success"]) ?? false
        let data = JSONLookup.object(object["data"])
        let error = JSONLookup.string(object["error"])

        switch command {
        case "get_state":
            if success, let data {
                applyState(data)
            }
            guard !didExit else { return }
            if awaitingSettle || snapshot.phase == .streaming {
                if !success, let error {
                    appendStatus(error)
                }
                return
            }
            snapshot.phase = .ready
            snapshot.statusLine = success ? connectedStatus() : (error ?? "get_state failed")
        case "get_commands":
            guard success, let commands = JSONLookup.array(data?["commands"]) else {
                if let error { appendStatus(error) }
                return
            }
            snapshot.commands = commands.compactMap(slashCommand(from:))
        case "get_available_models":
            guard success, let models = JSONLookup.array(data?["models"]) else {
                if let error { appendStatus(error) }
                return
            }
            snapshot.models = models.compactMap(modelChoice(from:))
        case "get_available_thinking_levels":
            guard success else {
                if let error { appendStatus(error) }
                return
            }
            snapshot.thinkingLevels = JSONLookup.strings(data?["levels"])
        case "get_fork_messages":
            guard success, let messages = JSONLookup.array(data?["messages"]) else {
                if let error { appendStatus(error) }
                return
            }
            snapshot.forkPoints = messages.compactMap(forkPoint(from:))
        case "get_messages":
            guard !awaitingSettle, snapshot.phase != .streaming else { return }
            guard success, let messages = JSONLookup.array(data?["messages"]) else {
                if let error { appendStatus(error) }
                return
            }
            snapshot.messages = messages.compactMap(chatMessage(from:))
        case "set_model":
            guard success, let data else {
                appendStatus(error ?? "Couldn't change the model.")
                return
            }
            applyModelObject(data)
        case "set_thinking_level", "set_session_name":
            if !success, let error {
                appendStatus(error)
            }
        case "new_session", "switch_session", "fork", "clone":
            applySessionChange(command, success: success, data: data, error: error)
        case "prompt":
            guard success else {
                appendStatus(error ?? "Prompt was rejected.")
                finishRun(status: connectedStatus())
                return
            }
            let disposition = JSONLookup.string(data?["disposition"])
            if disposition == "handled" {
                appendStatus("Brian handled that without starting a run.")
                finishRun(status: "Handled without a run")
                return
            }
            guard awaitingSettle, !didExit else { return }
            snapshot.phase = .streaming
            if disposition == "queued" {
                snapshot.statusLine = "Queued"
            } else if snapshot.statusLine == "Sending…" {
                snapshot.statusLine = "Replying…"
            }
        case "abort":
            if success {
                snapshot.statusLine = "Stopping…"
            } else if let error {
                appendStatus(error)
            }
        case "parse":
            appendStatus(error ?? "Brian could not parse a command.")
        default:
            if !success, let error {
                appendStatus(error)
            }
        }
    }

    private mutating func applyState(_ data: [String: Any]) {
        snapshot.sessionID = JSONLookup.string(data["sessionId"])
        snapshot.sessionFile = JSONLookup.string(data["sessionFile"])
        snapshot.sessionName = JSONLookup.string(data["sessionName"])
        snapshot.thinkingLevel = JSONLookup.string(data["thinkingLevel"])
        if let model = JSONLookup.object(data["model"]) {
            applyModelObject(model)
        } else {
            snapshot.modelLabel = nil
        }
    }

    private mutating func applyModelObject(_ model: [String: Any]) {
        let provider = JSONLookup.string(model["provider"]) ?? ""
        let identifier = JSONLookup.string(model["id"]) ?? ""
        let label = [provider, identifier].filter { !$0.isEmpty }.joined(separator: " / ")
        snapshot.modelLabel = label.isEmpty ? nil : label
    }

    private mutating func applySessionChange(
        _ command: String,
        success: Bool,
        data: [String: Any]?,
        error: String?
    ) {
        guard success else {
            if let error { appendStatus(error) }
            return
        }
        if JSONLookup.bool(data?["cancelled"]) == true {
            appendStatus("Brian cancelled that session change.")
            return
        }
        snapshot.messages = []
        textBlocks = [:]
        openAssistantID = nil
        awaitingSettle = false
        if !didExit {
            snapshot.phase = .ready
        }
        switch command {
        case "new_session":
            snapshot.statusLine = "New session"
        case "switch_session":
            snapshot.statusLine = "Switched session"
        case "fork":
            snapshot.statusLine = "Forked session"
        case "clone":
            snapshot.statusLine = "Cloned session"
        default:
            snapshot.statusLine = "Session changed"
        }
    }

    private func slashCommand(from value: Any) -> SlashCommand? {
        guard let object = JSONLookup.object(value), let name = JSONLookup.string(object["name"]), !name.isEmpty else {
            return nil
        }
        return SlashCommand(
            name: name,
            detail: JSONLookup.string(object["description"]) ?? "",
            source: JSONLookup.string(object["source"]) ?? ""
        )
    }

    private func modelChoice(from value: Any) -> ModelChoice? {
        guard let object = JSONLookup.object(value),
              let provider = JSONLookup.string(object["provider"]), !provider.isEmpty,
              let modelID = JSONLookup.string(object["id"]), !modelID.isEmpty
        else { return nil }
        return ModelChoice(
            provider: provider,
            modelID: modelID,
            name: JSONLookup.string(object["name"]) ?? modelID,
            reasoning: JSONLookup.bool(object["reasoning"]) ?? false
        )
    }

    private func forkPoint(from value: Any) -> ForkPoint? {
        guard let object = JSONLookup.object(value),
              let entryID = JSONLookup.string(object["entryId"]), !entryID.isEmpty
        else { return nil }
        return ForkPoint(entryID: entryID, text: JSONLookup.string(object["text"]) ?? "")
    }

    private func chatMessage(from value: Any) -> ChatMessage? {
        guard let object = JSONLookup.object(value) else { return nil }
        let text = visibleText(object["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch JSONLookup.string(object["role"]) {
        case "user":
            return ChatMessage(role: .user, text: text)
        case "assistant":
            return ChatMessage(role: .assistant, text: text)
        default:
            return nil
        }
    }

    private func visibleText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        guard let blocks = JSONLookup.array(content) else { return "" }
        return blocks.compactMap { block -> String? in
            guard let block = JSONLookup.object(block) else { return nil }
            guard JSONLookup.string(block["type"]) == "text" else { return nil }
            return JSONLookup.string(block["text"])
        }.joined()
    }

    private mutating func applyMessageStart(_ object: [String: Any]) {
        guard let message = JSONLookup.object(object["message"]) else { return }
        guard JSONLookup.string(message["role"]) == "assistant" else { return }
        ensureOpenAssistant()
        guard !didExit else { return }
        snapshot.phase = .streaming
    }

    private mutating func applyMessageUpdate(_ object: [String: Any]) {
        guard let event = JSONLookup.object(object["assistantMessageEvent"]) else { return }
        let eventType = JSONLookup.string(event["type"]) ?? ""
        let index = JSONLookup.int(event["contentIndex"]) ?? 0
        switch eventType {
        case "text_delta":
            ensureOpenAssistant()
            textBlocks[index, default: ""].append(JSONLookup.string(event["delta"]) ?? "")
            writeBlocksToOpenAssistant()
            markStreaming("Replying…")
        case "text_end":
            guard let content = textContent(event["content"]) else { return }
            ensureOpenAssistant()
            textBlocks[index] = content
            writeBlocksToOpenAssistant()
        case "thinking_delta":
            markStreaming("Thinking…")
        case "toolcall_start":
            let name = JSONLookup.string(event["toolName"]) ?? "tool"
            appendStatus("Tool call: \(name)")
        case "error":
            appendStatus(errorText(event["error"]) ?? "The model stream failed.")
        default:
            return
        }
    }

    private mutating func applyMessageEnd(_ object: [String: Any]) {
        guard let message = JSONLookup.object(object["message"]) else { return }
        guard JSONLookup.string(message["role"]) == "assistant" else { return }
        ensureOpenAssistant()
        if let text = assistantVisibleText(message), !text.isEmpty, let id = openAssistantID, let index = self.index(of: id) {
            snapshot.messages[index].text = text
        }
        let stopReason = JSONLookup.string(message["stopReason"])
        if stopReason == "error" {
            appendStatus(JSONLookup.string(message["errorMessage"]) ?? "The model returned an error.")
        } else if stopReason == "aborted" {
            appendStatus("Stopped.")
        }
        if let id = openAssistantID, let index = self.index(of: id) {
            snapshot.messages[index].isComplete = true
        }
        openAssistantID = nil
        textBlocks = [:]
    }

    private mutating func applySettled(aborted: Bool) {
        closeOpenAssistant()
        finishRun(status: aborted ? "Stopped" : connectedStatus())
    }

    private mutating func applyDelivery(_ object: [String: Any]) {
        guard let delivery = JSONLookup.object(object["delivery"]) else { return }
        guard let index = snapshot.messages.lastIndex(where: { $0.role == .assistant }) else { return }
        snapshot.messages[index].deliveryJSON = JSONLookup.jsonString(delivery)
        let text = JSONLookup.string(delivery["text"]) ?? ""
        if snapshot.messages[index].text.isEmpty, !text.isEmpty {
            snapshot.messages[index].text = text
        }
    }

    private mutating func applyExtensionUI(_ object: [String: Any]) -> [RpcEffect] {
        let method = JSONLookup.string(object["method"]) ?? "dialog"
        let id = JSONLookup.string(object["id"]) ?? ""
        switch method {
        case "notify":
            if let message = JSONLookup.string(object["message"]), !message.isEmpty {
                appendStatus(message)
            }
            return []
        case "setStatus":
            if let text = JSONLookup.string(object["statusText"]), !text.isEmpty {
                snapshot.statusLine = text
            }
            return []
        case "setWidget", "setTitle", "set_editor_text":
            return []
        case "select", "confirm", "input", "editor":
            let title = JSONLookup.string(object["title"]) ?? method
            appendStatus("Brian asked for “\(title)” (\(method)). This window cancelled that dialog.")
            return id.isEmpty ? [] : [.cancelExtensionUI(id: id)]
        default:
            guard !id.isEmpty else { return [] }
            appendStatus("Brian sent an unsupported UI request (\(method)). This window cancelled it.")
            return [.cancelExtensionUI(id: id)]
        }
    }

    private mutating func ensureOpenAssistant() {
        if let id = openAssistantID, let index = self.index(of: id), !snapshot.messages[index].isComplete {
            return
        }
        let message = ChatMessage(role: .assistant, text: "", isComplete: false)
        openAssistantID = message.id
        textBlocks = [:]
        snapshot.messages.append(message)
    }

    private mutating func writeBlocksToOpenAssistant() {
        guard let id = openAssistantID, let index = self.index(of: id) else { return }
        snapshot.messages[index].text = textBlocks.keys.sorted().map { textBlocks[$0] ?? "" }.joined()
    }

    private mutating func closeOpenAssistant() {
        if let id = openAssistantID, let index = self.index(of: id) {
            if snapshot.messages[index].text.isEmpty {
                snapshot.messages.remove(at: index)
            } else {
                snapshot.messages[index].isComplete = true
            }
        }
        openAssistantID = nil
        textBlocks = [:]
        awaitingSettle = false
    }

    private mutating func finishRun(status: String) {
        awaitingSettle = false
        guard !didExit else { return }
        snapshot.phase = .ready
        snapshot.statusLine = status
    }

    private mutating func markStreaming(_ status: String) {
        guard !didExit else { return }
        snapshot.phase = .streaming
        snapshot.statusLine = status
    }

    private mutating func appendStatus(_ text: String) {
        snapshot.messages.append(ChatMessage(role: .status, text: text))
    }

    private func connectedStatus() -> String {
        if let modelLabel = snapshot.modelLabel, !modelLabel.isEmpty {
            return "Connected · \(modelLabel)"
        }
        return "Connected"
    }

    private func index(of id: UUID) -> Int? {
        snapshot.messages.firstIndex { $0.id == id }
    }

    private func assistantVisibleText(_ message: [String: Any]) -> String? {
        guard let content = message["content"] else { return nil }
        if let text = content as? String { return text }
        guard let blocks = JSONLookup.array(content) else { return nil }
        let parts = blocks.compactMap { block -> String? in
            guard let block = JSONLookup.object(block) else { return nil }
            guard JSONLookup.string(block["type"]) == "text" else { return nil }
            return JSONLookup.string(block["text"])
        }
        return parts.joined()
    }

    private func textContent(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        if let block = JSONLookup.object(value) { return JSONLookup.string(block["text"]) }
        return nil
    }

    private func errorText(_ value: Any?) -> String? {
        if let text = JSONLookup.string(value) { return text }
        if let object = JSONLookup.object(value) {
            return JSONLookup.string(object["message"]) ?? JSONLookup.string(object["error"])
        }
        return nil
    }
}
