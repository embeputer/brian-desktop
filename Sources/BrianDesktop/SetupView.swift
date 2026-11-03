#if os(macOS)
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: DesktopModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose how this Mac talks to Brian. The choice is saved for the next launch.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                remoteSection
                localSection

                if let setupError = model.setupError, !setupError.isEmpty {
                    Text(setupError)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connect to a remote Brian")
                .font(.headline)
            Text("Address of a machine running brian serve. The reply arrives as one finished message.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("host:7333", text: $model.remoteAddress)
                .textFieldStyle(.roundedBorder)
            SecureField("Access token", text: $model.remoteToken)
                .textFieldStyle(.roundedBorder)
            Text("The token is the bearer value in that machine's serve.json.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Connect") {
                model.startRemote()
            }
            .disabled(model.isBusy)
        }
    }

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Run Brian on this Mac")
                .font(.headline)
            Text("Starts brian in RPC mode and streams the reply. If brian is not on PATH, the app installs it with npm.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Executable path, optional", text: $model.executablePath)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            Button("Install and start") {
                model.startLocal()
            }
            .disabled(model.isBusy)
            if model.isBusy {
                ProgressView("Working…")
                    .controlSize(.small)
            }
        }
    }
}
#endif
