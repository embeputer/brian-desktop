#if os(macOS)
import AppKit
import CoreText
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            VStack(spacing: 22) {
                AppMark()
                VStack(spacing: 10) {
                    Text("Brian")
                        .font(NewSpiritFont.font(size: 72))
                        .foregroundStyle(.black)
                        .accessibilityAddTraits(.isHeader)
                    Text("One agent for work, school, and life.")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 28)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
        .onAppear { NewSpiritFont.registerBundledFonts() }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onContinue) {
                HStack(spacing: 12) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("Continue")
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
    }
}

enum NewSpiritFont {
    private static let candidates = ["New Spirit", "NewSpirit-Regular", "PP New Spirit", "PPNewSpirit-Regular"]
    private static var didRegister = false

    static func registerBundledFonts() {
        guard !didRegister else { return }
        didRegister = true
        for url in bundledFontURLs() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(size: CGFloat) -> Font {
        registerBundledFonts()
        for name in candidates {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size)
            }
        }
        return .custom("New Spirit", size: size)
    }

    private static func bundledFontURLs() -> [URL] {
        var directories: [URL] = []
        if let resources = Bundle.main.resourceURL {
            directories.append(resources)
            directories.append(resources.appendingPathComponent("Fonts"))
        }
        let besideExecutable = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts")
        directories.append(besideExecutable)
        return directories.flatMap(fontFiles(in:))
    }

    private static func fontFiles(in directory: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return items.filter { ["otf", "ttf", "otc", "ttc"].contains($0.pathExtension.lowercased()) }
    }
}

private struct AppMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.34),
                            Color(white: 0.14),
                            Color(white: 0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            RadialGradient(
                colors: [Color.white.opacity(0.34), Color.clear],
                center: UnitPoint(x: 0.32, y: 0.22),
                startRadius: 2,
                endRadius: 78
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Text("B")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: -3)
        }
        .frame(width: 96, height: 96)
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)
        .accessibilityHidden(true)
    }
}
#endif
