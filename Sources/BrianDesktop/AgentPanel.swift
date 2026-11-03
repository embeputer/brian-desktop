#if os(macOS)
import BrianClient
import SwiftUI

enum AgentSection: String, CaseIterable, Identifiable {
    case session
    case model
    case commands
    case skills
    case memory
    case routines
    case mcp
    case signIn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session:
            return "Session"
        case .model:
            return "Model"
        case .commands:
            return "Commands"
        case .skills:
            return "Skills"
        case .memory:
            return "Memory"
        case .routines:
            return "Routines"
        case .mcp:
            return "MCP"
        case .signIn:
            return "Sign-in"
        }
    }
}

struct AgentPanel: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var section: AgentSection = .session

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Section", selection: $section) {
                    ForEach(AgentSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer()
                if workbench.busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Reload") { reload() }
                    .disabled(workbench.busy)
            }
            .padding(12)
            Divider()
            ScrollView {
                sectionBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            if !workbench.notice.isEmpty {
                Divider()
                Text(workbench.notice)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 320)
        .onAppear { reload() }
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section {
        case .session:
            SessionSection(model: model)
        case .model:
            ModelSection(model: model, workbench: workbench)
        case .commands:
            CommandsSection(model: model)
        case .skills:
            SkillsSection(model: model, workbench: workbench)
        case .memory:
            MemorySection(model: model, workbench: workbench)
        case .routines:
            RoutinesSection(model: model, workbench: workbench)
        case .mcp:
            McpSection(model: model, workbench: workbench)
        case .signIn:
            SignInSection(model: model, workbench: workbench)
        }
    }

    private func reload() {
        model.refreshSurface()
        workbench.reload(executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }
}

struct RemoteTools: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remote Brian")
                .font(.headline)
            Text("This connection is brian serve. It can send a prompt and read GET /v1/status. MCP servers, skills, memory, models, and sessions are not on that API.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = model.snapshot.remoteSummary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Button("Refresh status") { model.refreshRemoteStatus() }
            Spacer()
        }
        .padding(12)
        .frame(width: 320, alignment: .topLeading)
        .onAppear { model.refreshRemoteStatus() }
    }
}

private func labeled(_ title: String, _ value: String?) -> some View {
    let shown = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = (shown?.isEmpty == false ? shown : nil) ?? "—"
    return VStack(alignment: .leading, spacing: 2) {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(2)
    }
}

private struct SessionSection: View {
    @ObservedObject var model: DesktopModel
    @State private var name = ""
    @State private var path = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.snapshot.sessionName ?? "Untitled session")
                .font(.headline)
            labeled("Id", model.snapshot.sessionID)
            labeled("File", model.snapshot.sessionFile)
            Text("RPC can start, rename, and open a session file. It does not list saved sessions. brian status only counts them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Session name", text: $name)
                .textFieldStyle(.roundedBorder)
            Button("Rename") { model.renameSession(name) }
                .disabled(!model.snapshot.canSend || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            HStack {
                Button("New session") { model.startNewSession() }
                Button("Clone") { model.cloneSession() }
            }
            .disabled(!model.snapshot.canSend)
            TextField("Session file path", text: $path)
                .textFieldStyle(.roundedBorder)
            Button("Open file") { model.openSessionFile(path) }
                .disabled(!model.snapshot.canSend || path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !model.snapshot.forkPoints.isEmpty {
                Text("Fork from")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(model.snapshot.forkPoints) { point in
                    Button(point.text.isEmpty ? point.entryID : point.text) {
                        model.forkSession(entryID: point.entryID)
                    }
                    .disabled(!model.snapshot.canSend)
                    .lineLimit(2)
                }
            }
        }
        .onAppear { name = model.snapshot.sessionName ?? "" }
    }
}

private struct ModelSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var provider = ""
    @State private var modelID = ""
    @State private var level = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.snapshot.modelLabel ?? "No model selected")
                .font(.headline)
            if let saved = workbench.defaultModel {
                Text("Saved default \(saved)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("The fields below call RPC set_model for this session. Save default runs brian model provider/id.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.snapshot.models.isEmpty {
                Text("Brian has not listed models yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.snapshot.models) { choice in
                    Button(choice.name == choice.modelID ? choice.id : "\(choice.name) · \(choice.id)") {
                        provider = choice.provider
                        modelID = choice.modelID
                    }
                    .buttonStyle(.plain)
                    .lineLimit(2)
                }
            }
            TextField("Provider", text: $provider)
                .textFieldStyle(.roundedBorder)
            TextField("Model id", text: $modelID)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Use") { model.useModel(provider: provider, modelID: modelID) }
                    .disabled(!model.snapshot.canSend)
                Button("Save default") {
                    workbench.perform(
                        .modelSet(provider: provider, modelID: modelID),
                        executablePath: model.executablePath,
                        workingDirectory: directory
                    )
                }
                .disabled(workbench.busy)
            }
            TextField("Thinking level", text: $level)
                .textFieldStyle(.roundedBorder)
            if !model.snapshot.thinkingLevels.isEmpty {
                Text(model.snapshot.thinkingLevels.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Set thinking") { model.useThinkingLevel(level.isEmpty ? (model.snapshot.thinkingLevel ?? "") : level) }
                .disabled(!model.snapshot.canSend)
            if let current = model.snapshot.thinkingLevel {
                Text("Current thinking \(current)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            level = model.snapshot.thinkingLevel ?? ""
            if let current = model.snapshot.models.first(where: { model.snapshot.modelLabel?.contains($0.modelID) == true }) {
                provider = current.provider
                modelID = current.modelID
            }
        }
    }

    private var directory: URL { URL(fileURLWithPath: model.workingDirectoryPath) }
}

private struct CommandsSection: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type / in the message box, or pick a command. Brian runs it with the prompt command.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.snapshot.commands.isEmpty {
                Text("No slash commands reported.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.snapshot.commands) { command in
                Button {
                    model.insertCommand(command.name)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("/\(command.name)")
                        if !command.detail.isEmpty {
                            Text(command.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SkillsSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var source = ""
    @State private var skillName = ""
    @State private var skillDescription = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Skills come from brian skill. Invoking one in chat is the slash command skill:name.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if workbench.skills.isEmpty {
                Text("No skills loaded.")
                    .foregroundStyle(.secondary)
            }
            ForEach(workbench.skills) { skill in
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name)
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Show") { capture(.skillShow(name: skill.name)) }
                        Button("Remove") { perform(.skillRemove(name: skill.name)) }
                        Button("Use") { model.insertCommand("skill:\(skill.name)") }
                    }
                }
            }
            TextField("Path to SKILL.md or a directory", text: $source)
                .textFieldStyle(.roundedBorder)
            Button("Install skill") { perform(.skillAdd(source: source, force: false)) }
            TextField("New skill name", text: $skillName)
                .textFieldStyle(.roundedBorder)
            TextField("Description", text: $skillDescription)
                .textFieldStyle(.roundedBorder)
            Button("Create skill") { perform(.skillNew(name: skillName, description: skillDescription)) }
        }
    }

    private func perform(_ command: BrianCliCommand) {
        workbench.perform(command, executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }

    private func capture(_ command: BrianCliCommand) {
        workbench.capture(command, executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }
}

private struct MemorySection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var query = ""
    @State private var target = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let status = workbench.status {
                Text("\(status.memoryNotes) notes in the vault")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
            Button("Search") {
                workbench.searchMemory(
                    text: query,
                    executablePath: model.executablePath,
                    workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath)
                )
            }
            .disabled(workbench.busy)
            notes(workbench.searchResults, title: "Search")
            notes(workbench.notes, title: "Notes")
            TextField("Folder/Name", text: $target)
                .textFieldStyle(.roundedBorder)
            TextField("Note", text: $content, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
            Button("Add note") {
                workbench.perform(
                    .memoryAdd(target: target, content: content),
                    executablePath: model.executablePath,
                    workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath)
                )
            }
            .disabled(workbench.busy)
        }
    }

    private func notes(_ items: [MemoryNoteSummary], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !items.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { note in
                Button(note.relativePath) {
                    workbench.capture(
                        .memoryShow(note: note.relativePath),
                        executablePath: model.executablePath,
                        workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RoutinesSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var text = ""
    @State private var when = ""
    @State private var every = ""
    @State private var task = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The routines daemon is not started from this window. It would run until the process is killed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if workbench.routines.isEmpty {
                Text("No routines.")
                    .foregroundStyle(.secondary)
            }
            ForEach(workbench.routines) { routine in
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.payload)
                        .lineLimit(2)
                    Text("\(routine.id) · \(routine.type) · \(routine.when)\(routine.enabled ? "" : " · paused")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button(routine.enabled ? "Pause" : "Resume") {
                            perform(routine.enabled ? .routinesPause(id: routine.id) : .routinesResume(id: routine.id))
                        }
                        Button("Remove") { perform(.routinesRemove(id: routine.id)) }
                        Button("Run") { perform(.routinesRun(id: routine.id)) }
                    }
                }
            }
            Button("History") { capture(.routinesHistory(id: nil)) }
            TextField("Text", text: $text)
                .textFieldStyle(.roundedBorder)
            TextField("When, such as 30m or tomorrow 9am", text: $when)
                .textFieldStyle(.roundedBorder)
            TextField("Repeat, optional", text: $every)
                .textFieldStyle(.roundedBorder)
            Toggle("Run the text as a prompt", isOn: $task)
            Button("Add routine") {
                perform(.routinesAdd(text: text, when: when, every: every.isEmpty ? nil : every, task: task))
            }
            .disabled(workbench.busy)
        }
    }

    private func perform(_ command: BrianCliCommand) {
        workbench.perform(command, executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }

    private func capture(_ command: BrianCliCommand) {
        workbench.capture(command, executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }
}

private struct McpSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var name = ""
    @State private var command = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("brian mcp list connects to each server. Login opens the system browser and waits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let note = workbench.mcp.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(workbench.mcp.errors, id: \.self) { error in
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if workbench.mcp.servers.isEmpty {
                Text("No MCP servers configured.")
                    .foregroundStyle(.secondary)
            }
            ForEach(workbench.mcp.servers) { server in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(server.name) · \(server.state)")
                    Text(server.transport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if !server.tools.isEmpty {
                        Text(server.tools.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let error = server.error, !error.isEmpty {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(3)
                    }
                    HStack {
                        Button("Sign in") { perform(.mcpLogin(name: server.name)) }
                        Button("Sign out") { perform(.mcpLogout(name: server.name)) }
                        Button("Remove") { perform(.mcpRemove(name: server.name)) }
                    }
                }
            }
            TextField("Server name", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Command, such as npx -y server", text: $command)
                .textFieldStyle(.roundedBorder)
            Button("Add command") {
                let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
                perform(.mcpAddCommand(name: name, command: tokens))
            }
            TextField("HTTP URL", text: $url)
                .textFieldStyle(.roundedBorder)
            Button("Add URL") { perform(.mcpAddURL(name: name, url: url)) }
        }
    }

    private func perform(_ command: BrianCliCommand) {
        workbench.perform(command, executablePath: model.executablePath, workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath))
    }
}

private struct SignInSection: View {
    @ObservedObject var model: DesktopModel
    @ObservedObject var workbench: AgentWorkbench
    @State private var token = ""
    @State private var url = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("brian connect and brian login need a terminal, so xAI and Codex sign-in stay there. This window checks saved credentials with brian auth check --json --no-refresh and does not print the credential.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if workbench.providers.isEmpty {
                Text("No provider check yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(workbench.providers) { provider in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(provider.provider) · \(provider.status)")
                    if let reason = provider.reason, !reason.isEmpty {
                        Text(reason.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let authType = provider.authType, !authType.isEmpty {
                        Text(authType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("Beeper accepts a token without a terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Beeper access token", text: $token)
                .textFieldStyle(.roundedBorder)
            TextField("Beeper URL, optional", text: $url)
                .textFieldStyle(.roundedBorder)
            Button("Connect Beeper") {
                workbench.perform(
                    .connectBeeper(token: token, url: url.isEmpty ? nil : url),
                    executablePath: model.executablePath,
                    workingDirectory: URL(fileURLWithPath: model.workingDirectoryPath)
                )
                token = ""
            }
            .disabled(workbench.busy || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}
#endif
