#if os(macOS)
import AppKit
import BrianClient
import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearancePreference.solidKey) private var solid = false
    @AppStorage(AppearancePreference.transparencyKey) private var transparency = AppearancePreference.defaultTransparency

    var body: some View {
        Form {
            Section {
                Toggle("Fully solid", isOn: $solid)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transparency")
                    Slider(value: $transparency, in: 0...AppearancePreference.maximumTransparency)
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(solid)
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 220)
        .background(WindowTransparency(alpha: windowAlpha))
    }

    private var windowAlpha: CGFloat {
        CGFloat(AppearancePreference.opacity(solid: solid, transparency: transparency))
    }

    private var caption: String {
        if solid {
            return "The window is fully solid."
        }
        return "\(Int((transparency * 100).rounded()))% transparent"
    }
}

struct WindowTransparency: NSViewRepresentable {
    var alpha: CGFloat

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let alpha = alpha
        DispatchQueue.main.async {
            for window in NSApplication.shared.windows {
                window.isOpaque = alpha >= 0.999
                window.alphaValue = alpha
            }
        }
    }
}
#endif
