#if os(macOS)
import AppKit
import BrianClient
import ObjectiveC
import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage(AppearancePreference.solidKey) private var solid = false
    @AppStorage(AppearancePreference.transparencyKey) private var transparency = AppearancePreference.defaultTransparency
    @AppStorage(AppearancePreference.blurKey) private var blur = AppearancePreference.defaultBlur

    var body: some View {
        Form {
            Section {
                Toggle("Fully solid", isOn: $solid)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transparency")
                    Slider(value: $transparency, in: 0...AppearancePreference.maximumTransparency)
                    Text(transparencyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(solid)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Blur")
                    Slider(value: $blur, in: 0...AppearancePreference.maximumBlur)
                    Text(blurCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disabled(solid)
            } header: {
                Text("Appearance")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460, height: 380)
        .background {
            WindowVeil(fill: appearanceFill, opacity: veil)
        }
        .background(WindowTransparency(solid: solid, blur: appliedBlur))
        .clearWindowContainer()
    }

    private var veil: Double {
        AppearancePreference.opacity(solid: solid, transparency: transparency)
    }

    private var appliedBlur: CGFloat {
        CGFloat(AppearancePreference.appliedBlur(solid: solid, blur: blur))
    }

    private var appearanceFill: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var transparencyCaption: String {
        if solid {
            return "The window is fully solid."
        }
        return "\(Int((transparency * 100).rounded()))% transparent"
    }

    private var blurCaption: String {
        if solid {
            return "Blur stays off while the window is fully solid."
        }
        let percent = Int((AppearancePreference.blurAmount(blur) * 100).rounded())
        if percent == 0 {
            return "No blur. Transparent areas stay clear."
        }
        return "\(percent)% blur on the transparent background"
    }
}

/// A translucent wash over the frosted desktop. Text and controls sit above it, so they stay sharp.
struct WindowVeil: View {
    var fill: Color
    var opacity: Double

    var body: some View {
        fill.opacity(opacity)
            .allowsHitTesting(false)
    }
}

struct WindowTransparency: NSViewRepresentable {
    var solid: Bool
    var blur: CGFloat

    func makeCoordinator() -> WindowBackdrop.Coordinator {
        WindowBackdrop.Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        view.setContentHuggingPriority(.fittingSizeCompression, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let solid = solid
        let blur = blur
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            WindowBackdrop.apply(anchor: nsView, solid: solid, blur: blur, coordinator: coordinator)
        }
    }
}

enum WindowBackdrop {
    fileprivate static let blurIdentifier = NSUserInterfaceItemIdentifier("dev.brian.desktop.backdrop-blur")

    final class Coordinator {
        fileprivate var blurView: BackdropBlurView?
    }

    static func apply(anchor: NSView, solid: Bool, blur: CGFloat, coordinator: Coordinator) {
        HostingOpacity.install()
        guard let window = anchor.window, let content = window.contentView else {
            return
        }
        window.alphaValue = 1
        window.titlebarAppearsTransparent = false

        let blurView = coordinator.blurView ?? BackdropBlurView(frame: content.bounds)
        coordinator.blurView = blurView
        blurView.identifier = blurIdentifier

        if solid || blur <= 0.001 {
            restoreHostingView(in: window, blurView: blurView)
            ClearWindows.unmark(window)
            blurView.removeFromSuperview()
            window.isOpaque = solid
            window.backgroundColor = solid ? .windowBackgroundColor : .clear
            return
        }

        guard let host = hostingView(in: window) else { return }
        ClearWindows.mark(window)
        window.isOpaque = false
        window.backgroundColor = .clear
        // A transparent sibling punches through to the desktop and skips the frost.
        // The hosting view has to live inside the effect view so its clear areas show the blur.
        if window.contentView !== blurView {
            blurView.frame = host.frame
            blurView.autoresizingMask = [.width, .height]
            window.contentView = blurView
            blurView.addSubview(host)
            host.frame = blurView.bounds
            host.autoresizingMask = [.width, .height]
        }
        let minimum = host.fittingSize
        if minimum.width >= 100, minimum.height >= 100 {
            window.contentMinSize = minimum
            let contentSize = window.contentRect(forFrameRect: window.frame).size
            if contentSize.width + 1 < minimum.width || contentSize.height + 1 < minimum.height {
                window.setContentSize(minimum)
            }
        }
        blurView.material = material(for: blur)
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.alphaValue = 1
        clearOpaqueSurfaces(in: host)
    }

    private static func hostingView(in window: NSWindow) -> NSView? {
        guard let content = window.contentView else { return nil }
        if content is BackdropBlurView {
            return content.subviews.first { String(describing: type(of: $0)).contains("HostingView") } ?? content.subviews.first
        }
        return content
    }

    private static func restoreHostingView(in window: NSWindow, blurView: BackdropBlurView) {
        guard window.contentView === blurView, let host = hostingView(in: window) else { return }
        host.removeFromSuperview()
        window.contentView = host
    }

    private static func material(for blur: CGFloat) -> NSVisualEffectView.Material {
        if blur < 0.34 {
            return .popover
        }
        if blur < 0.67 {
            return .headerView
        }
        return .underWindowBackground
    }

    /// SwiftUI's hosting view and scroll views paint an opaque fill that hides the desktop blur.
    private static func clearOpaqueSurfaces(in view: NSView) {
        func visit(_ view: NSView) {
            let name = String(describing: type(of: view))
            if name.contains("HostingView") {
                view.wantsLayer = true
                view.layer?.isOpaque = false
                view.layer?.backgroundColor = NSColor.clear.cgColor
            }
            if let scroll = view as? NSScrollView {
                scroll.drawsBackground = false
                scroll.backgroundColor = .clear
                scroll.contentView.drawsBackground = false
            }
            view.subviews.forEach(visit)
        }
        visit(view)
    }

}

private final class BackdropBlurView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// `NSHostingView` reports itself as opaque, so AppKit flattens the translucent veil onto a solid fill.
private enum ClearWindows {
    private static let windows = NSHashTable<NSWindow>.weakObjects()

    static func mark(_ window: NSWindow) {
        windows.add(window)
    }

    static func unmark(_ window: NSWindow) {
        windows.remove(window)
    }

    static func contains(_ window: NSWindow) -> Bool {
        windows.contains(window)
    }
}

extension View {
    /// Drops the system's solid window fill on macOS 15 and later. Earlier systems rely on the AppKit backdrop.
    @ViewBuilder
    func clearWindowContainer() -> some View {
        if #available(macOS 15, *) {
            containerBackground(.clear, for: .window)
        } else {
            self
        }
    }
}

private enum HostingOpacity {
    private static var installed = false
    private static var original: IMP?

    static func install() {
        guard !installed else { return }
        let hostingClass: AnyClass = NSHostingView<AnyView>.self
        let selector = #selector(getter: NSView.isOpaque)
        guard let method = class_getInstanceMethod(hostingClass, selector) else { return }
        installed = true
        original = method_getImplementation(method)
        let block: @convention(block) (AnyObject) -> Bool = { object in
            if let view = object as? NSView, let window = view.window, ClearWindows.contains(window) {
                return false
            }
            guard let original else { return true }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(original, to: Getter.self)(object, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}
#endif
