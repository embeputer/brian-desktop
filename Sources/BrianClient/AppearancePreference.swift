import Foundation

/// How see-through the desktop window is.
///
/// `transparency` is 0 for a solid window and 1 for a fully clear one.
/// The default, 0.10, leaves the window at 90% opacity: a little transparent.
/// `solid` overrides the slider and forces a fully opaque window.
public enum AppearancePreference {
    public static let solidKey = "dev.brian.desktop.appearance.solid"
    public static let transparencyKey = "dev.brian.desktop.appearance.transparency"
    public static let defaultTransparency = 0.10
    public static let maximumTransparency = 0.60

    public static func opacity(solid: Bool, transparency: Double) -> Double {
        if solid {
            return 1
        }
        let clamped = min(max(transparency, 0), maximumTransparency)
        return 1 - clamped
    }
}
