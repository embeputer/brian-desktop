#if os(macOS)
import BrianClient
import SwiftUI

struct UpdatePromptView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch controller.phase {
            case .available(let item):
                available(item)
            case .downloading(let item, let fraction):
                downloading(item, fraction: fraction)
            case .ready(let item):
                ready(item)
            case .failed(let message):
                failed(message)
            case .idle, .checking:
                Text(UpdatePromptCopy.availableTitle)
                    .font(.title3.weight(.semibold))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color.white)
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(isDownloading)
    }

    private var isDownloading: Bool {
        if case .downloading = controller.phase {
            return true
        }
        return false
    }

    private func available(_ item: ReleaseFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UpdatePromptCopy.availableTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
            Text(UpdatePromptCopy.availableMessage(
                offeredVersion: item.version,
                currentVersion: controller.currentVersion.version
            ))
            .foregroundStyle(Color(white: 0.2))
            .fixedSize(horizontal: false, vertical: true)
            if !item.releaseNotes.isEmpty {
                Text(UpdatePromptCopy.releaseNotesHeading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(item.releaseNotes)
                        .font(.callout)
                        .foregroundStyle(.black)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
            buttons {
                Button(UpdatePromptCopy.laterButton) { controller.later() }
                Button(UpdatePromptCopy.installButton) { controller.install() }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
            }
        }
    }

    private func downloading(_ item: ReleaseFeedItem, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UpdatePromptCopy.downloadingTitle(version: item.version))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
            if fraction > 0 {
                ProgressView(value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            buttons {
                Button(UpdatePromptCopy.cancelButton) { controller.cancelDownload() }
            }
        }
    }

    private func ready(_ item: ReleaseFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(UpdatePromptCopy.readyTitle(version: item.version))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
            Text(UpdatePromptCopy.readyMessage)
                .foregroundStyle(Color(white: 0.2))
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button(UpdatePromptCopy.laterButton) { controller.later() }
                Button(UpdatePromptCopy.relaunchButton) { controller.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Couldn't update Brian")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.black)
            Text(message)
                .foregroundStyle(Color(white: 0.2))
                .fixedSize(horizontal: false, vertical: true)
            buttons {
                Button(UpdatePromptCopy.closeButton) { controller.dismissFailure() }
            }
        }
    }

    private func buttons<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            Spacer()
            content()
        }
    }
}
#endif
