#if os(macOS)
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 28)
            VStack(spacing: 22) {
                AppMark()
                VStack(spacing: 8) {
                    Text("Brian")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.black)
                        .accessibilityAddTraits(.isHeader)
                    Text("One agent for work, school, and life.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(white: 0.36))
                        .multilineTextAlignment(.center)
                }
            }
            Spacer(minLength: 28)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button(action: onContinue) {
                Text("Continue")
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.black)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
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
