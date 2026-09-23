import AppKit

enum AppAppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system: nil
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}

/// One application-level override, inherited by existing and future windows/sheets.
/// A nil appearance intentionally keeps following macOS, including Auto changes.
@MainActor
final class AppearancePreferences {
    static let defaultsKey = "appearance.mode.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: AppAppearanceMode {
        get {
            defaults.string(forKey: Self.defaultsKey).flatMap(AppAppearanceMode.init(rawValue:))
                ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: Self.defaultsKey) }
    }

    func apply(to application: NSApplication = .shared) {
        application.appearance = mode.appearanceName.flatMap(NSAppearance.init(named:))
    }
}

/// Opaque, adaptive text colors. Never bake these into a layer without resolving
/// again on appearance changes. Native controls retain system focus/selection cues.
enum AppPalette {
    static let secondaryText = adaptive(
        "secondaryText", light: NSColor(white: 0.28, alpha: 1),
        dark: NSColor(white: 0.80, alpha: 1))
    static let warningText = adaptive(
        "warningText", light: NSColor(srgbRed: 0.47, green: 0.26, blue: 0.02, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.76, blue: 0.36, alpha: 1))
    static let errorText = adaptive(
        "errorText", light: NSColor(srgbRed: 0.70, green: 0.13, blue: 0.13, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.60, blue: 0.60, alpha: 1))

    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("MKVMagic.\(name)")) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua, .darkAqua, .accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua,
            ])
            return switch match {
            case .darkAqua: dark
            case .accessibilityHighContrastDarkAqua: NSColor(white: 0.92, alpha: 1)
            case .accessibilityHighContrastAqua: NSColor(white: 0.15, alpha: 1)
            default: light
            }
        }
    }
}
