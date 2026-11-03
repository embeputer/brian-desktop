#if os(macOS)
import AppKit
import BrianClient
import SwiftUI

struct ContentView: View {
    @StateObject private var model = DesktopModel()
    @State private var showsTools = false
    @FocusState private var composerFocused: Bool
    @AppStorage(AppearancePreference.solidKey) private var solidWindow = false
    @AppStorage(AppearancePreference.transparencyKey) private var transparency = AppearancePreference.defaultTransparency
    @AppStorage(AppearancePreference.blurKey) private var blur = AppearancePreference.defaultBlur

    var body: some View {
        NavigationStack {
            Group {
                switch model.launchStep {
                case .welcome:
                    WelcomeView(onContinue: model.continueFromWelcome)
                case .setup:
                    SetupView(model: model)
                case .ready:
                    chat
                }
            }
            .navigationTitle(model.launchStep == .ready ? "Brian" : "")
            .toolbar(model.launchStep == .ready ? .automatic : .hidden, for: .windowToolbar)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background {
            WindowVeil(fill: windowFill, opacity: veil)
        }
        .background(WindowTransparency(solid: solidWindow, blur: appliedBlur))
        .clearWindowContainer()
        .onAppear {
            model.connectIfNeeded()
            if model.launchStep == .ready {
                composerFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.stop()
        }
    }

    private var veil: Double {
        AppearancePreference.opacity(solid: solidWindow, transparency: transparency)
    }

    private var appliedBlur: CGFloat {
        CGFloat(AppearancePreference.appliedBlur(solid: solidWindow, blur: blur))
    }

    private var windowFill: Color {
        model.launchStep == .ready ? Color(nsColor: .textBackgroundColor) : Color.white
    }

    private var chat: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                connectionBar
                Divider()
                transcript
                if !model.snapshot.stderr.isEmpty {
                    Divider()
                    stderrDisclosure
                }
                Divider()
                composer
            }
            if showsTools {
                Divider()
                if model.settings?.mode == .remote {
                    RemoteTools(model: model)
                } else {
                    AgentPanel(model: model, workbench: model.workbench)
                }
            }
        }
    }

    private var connectionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(model.snapshot.statusLine)
                Text(model.snapshot.statusLine)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if model.snapshot.phase == .streaming {
                    Button("Stop") { model.abort() }
                } else {
                    Button("Reconnect") { model.reconnect() }
                        .disabled(model.isBusy)
                }
                Button("Change") { model.changeConnection() }
                Button(showsTools ? "Hide tools" : "Tools") { showsTools.toggle() }
            }
            Text(model.settings?.mode == .remote ? model.remoteAddress : model.executablePath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if model.settings?.mode != .remote {
                Text("Working directory \(model.workingDirectoryPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.snapshot.messages.isEmpty {
                        Text(emptyText)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(model.snapshot.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: scrollToken) { _, _ in
                guard let id = model.snapshot.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var stderrDisclosure: some View {
        DisclosureGroup("brian stderr") {
            Text(model.snapshot.stderr)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !slashSuggestions.isEmpty {
                ForEach(slashSuggestions.prefix(6)) { command in
                    Button {
                        model.insertCommand(command.name)
                    } label: {
                        HStack {
                            Text("/\(command.name)")
                            if !command.detail.isEmpty {
                                Text(command.detail)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(command.source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            composerField
        }
    }

    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message Brian", text: $model.prompt, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($composerFocused)
                .onSubmit { model.send() }
            Button {
                model.send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Send (⌘↩)")
            .accessibilityLabel("Send")
        }
        .padding(12)
    }

    private var slashSuggestions: [SlashCommand] {
        guard model.settings?.mode != .remote else { return [] }
        let trimmed = model.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/"), !trimmed.contains(" ") else { return [] }
        let query = String(trimmed.dropFirst()).lowercased()
        return model.snapshot.commands.filter { command in
            query.isEmpty || command.name.lowercased().contains(query)
        }
    }

    private var canSend: Bool {
        model.snapshot.canSend && !model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyText: String {
        switch model.snapshot.phase {
        case .idle, .launching:
            return model.settings?.mode == .remote ? "Connecting to brian serve." : "Starting brian."
        case .ready:
            return model.settings?.mode == .remote
                ? "Send a prompt. brian serve sends the whole reply at once."
                : "Send a prompt. The reply streams from brian."
        case .streaming:
            return model.settings?.mode == .remote ? "Waiting for the reply." : "Waiting for brian."
        case .failed(let message):
            return message
        case .exited:
            return "The brian process has exited. Reconnect to start it again."
        }
    }

    private var statusColor: Color {
        switch model.snapshot.phase {
        case .ready:
            return .green
        case .launching, .streaming:
            return .orange
        case .failed, .exited:
            return .red
        case .idle:
            return .secondary
        }
    }

    private var scrollToken: String {
        model.snapshot.messages.map { "\($0.id.uuidString):\($0.text.count):\($0.isComplete)" }.joined(separator: "|")
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 64)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                Text("Brian")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(assistantText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .status:
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var assistantText: String {
        if message.isComplete || message.text.isEmpty {
            return message.text
        }
        return message.text + "▍"
    }
}
#endif
