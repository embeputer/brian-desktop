#if os(macOS)
import SwiftUI

struct SetupView: View {
    @ObservedObject var model: DesktopModel
    @State private var showsRemoteForm = false

    var body: some View {
        ZStack {
            if showsRemoteForm {
                remoteForm
            } else {
                choice
            }
        }
        .preferredColorScheme(.light)
    }

    private var choice: some View {
        VStack(spacing: 36) {
            Text("How would you like to run brian?")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)

            HStack(alignment: .top, spacing: 16) {
                StartChoiceCard(title: "Run it locally", message: "Brian will be ran locally on your computer. Brian will not work when your computer is sleeping.") {
                    model.startLocal()
                } icon: {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 26))
                }
                .disabled(model.isBusy)

                StartChoiceCard(title: "Connect to a server", message: "Connect to a remote server or computer that is running brian. If configured correctly, brian will be always on.") {
                    model.setupError = nil
                    showsRemoteForm = true
                } icon: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 26))
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11, weight: .bold))
                            .offset(x: 7, y: -7)
                    }
                    .frame(width: 42, height: 30, alignment: .bottomLeading)
                }
                .disabled(model.isBusy)
            }

            if model.isBusy {
                ProgressView("Installing brian…")
                    .controlSize(.small)
            }

            status
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remoteForm: some View {
        VStack(spacing: 22) {
            Text("Connect to a server")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.black)

            VStack(alignment: .leading, spacing: 12) {
                TextField("host:7333", text: $model.remoteAddress)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.08)))
                SecureField("Access token", text: $model.remoteToken)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.black.opacity(0.08)))
                Text("The token is the bearer value in that machine's serve.json. Another machine needs https (a TLS proxy in front of serve) or an SSH tunnel to localhost. The reply arrives as one finished message.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Connect") {
                    model.startRemote()
                }
                .buttonStyle(.borderedProminent)
                .tint(.black)
                .disabled(model.isBusy)
            }
            .padding(22)
            .frame(width: 360)
            .background(Color(white: 0.975), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.08)))

            Button("Back") {
                model.setupError = nil
                showsRemoteForm = false
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(white: 0.35))

            status
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        VStack(spacing: 8) {
            if let setupError = model.setupError, !setupError.isEmpty {
                Text(setupError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            if model.canCancelSetup {
                Button("Cancel") { model.cancelSetup() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }
}

private struct StartChoiceCard<Icon: View>: View {
    let title: String
    let message: String
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                icon()
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.42))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)
            .frame(width: 250, height: 196, alignment: .topLeading)
            .background(hovering ? Color(white: 0.955) : Color(white: 0.975), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
#endif
