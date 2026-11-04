import Foundation

/// How see-through the desktop window is, and how hard the desktop behind it is blurred.
///
/// `transparency` is 0 for a solid background and 1 for a fully clear one.
/// The default, 0.10, leaves the background at 90% opacity: a little transparent.
/// `blur` is 0 for a clear view through those transparent parts and 1 for a full frost.
/// `solid` overrides both sliders and forces a fully opaque window.
public enum AppearancePreference {
    public static let solidKey = "dev.brian.desktop.appearance.solid"
    public static let transparencyKey = "dev.brian.desktop.appearance.transparency"
    public static let blurKey = "dev.brian.desktop.appearance.blur"
    public static let defaultTransparency = 0.10
    public static let maximumTransparency = 0.60
    public static let defaultBlur = 0.50
    public static let maximumBlur = 1.0

    public static func opacity(solid: Bool, transparency: Double) -> Double {
        if solid {
            return 1
        }
        let clamped = min(max(transparency, 0), maximumTransparency)
        return 1 - clamped
    }

    public static func blurAmount(_ blur: Double) -> Double {
        min(max(blur, 0), maximumBlur)
    }

    /// Blur applies only to a window that is allowed to be transparent.
    public static func appliedBlur(solid: Bool, blur: Double) -> Double {
        if solid {
            return 0
        }
        return blurAmount(blur)
    }
}
