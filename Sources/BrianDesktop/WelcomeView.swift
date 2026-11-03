#if os(macOS)
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Brian")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.black)
                Text("One agent for work, school, and life.")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(white: 0.42))
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                    .padding(.top, 14)
            }
        }
        .preferredColorScheme(.light)
    }
}
#endif
