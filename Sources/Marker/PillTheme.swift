import SwiftUI

/// The selection-action pill is one component with one behavior. Themes only
/// replace these seven colors; layout, typography, and motion stay shared.
struct PillTheme {
    let chip: Color
    let surface: Color
    let border: Color?
    let text: Color
    let dim: Color
    let accent: Color
    let success: Color
}

enum PillThemeChoice: String, CaseIterable, Identifiable {
    case ink
    case oled
    case catppuccin
    case gruvbox
    case tokyonight
    case rosepine

    var id: Self { self }

    var displayName: String {
        switch self {
        case .ink: "Ink"
        case .oled: "OLED"
        case .catppuccin: "Catppuccin"
        case .gruvbox: "Gruvbox"
        case .tokyonight: "Tokyo Night"
        case .rosepine: "Rosé Pine"
        }
    }

    /// Alpha for the shared accent-over-surface hover treatment. The rice
    /// palettes use their canonical 82/18 mix; HUD themes target their
    /// documented white-fill levels.
    var keycapHoverTintOpacity: Double {
        switch self {
        case .ink: 0.055
        case .oled: 0.11
        case .catppuccin, .gruvbox, .tokyonight, .rosepine: 0.18
        }
    }

    /// Ink and OLED are dark HUD palettes in both system appearances. Rice
    /// themes keep following the current macOS appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .ink, .oled: .dark
        case .catppuccin, .gruvbox, .tokyonight, .rosepine: nil
        }
    }

    func theme(for colorScheme: ColorScheme) -> PillTheme {
        switch self {
        case .ink:
            return PillTheme(
                chip: Color(red: 0.125, green: 0.122, blue: 0.133).opacity(0.94),
                surface: .white.opacity(0.09),
                border: nil,
                text: .white,
                dim: .white.opacity(0.8),
                accent: .white,
                success: Color(nsColor: .systemGreen)
            )

        case .oled:
            return PillTheme(
                chip: .black,
                surface: .white.opacity(0.10),
                border: .white.opacity(0.10),
                text: .white,
                dim: .white.opacity(0.8),
                accent: .white,
                success: .white
            )

        case .catppuccin:
            if colorScheme == .dark {
                return PillTheme(
                    chip: Self.color(0x1E1E2E),
                    surface: Self.color(0x313244),
                    border: Self.color(0x313244),
                    text: Self.color(0xCDD6F4),
                    dim: Self.color(0xCDD6F4, opacity: 0.60),
                    accent: Self.color(0xFAB387),
                    success: Self.color(0xA6E3A1)
                )
            }
            return PillTheme(
                chip: Self.color(0xEFF1F5),
                surface: Self.color(0xCCD0DA),
                border: Self.color(0xCCD0DA),
                text: Self.color(0x4C4F69),
                dim: Self.color(0x4C4F69, opacity: 0.62),
                accent: Self.color(0xFE640B),
                success: Self.color(0x40A02B)
            )

        case .gruvbox:
            if colorScheme == .dark {
                return PillTheme(
                    chip: Self.color(0x282828),
                    surface: Self.color(0x3C3836),
                    border: Self.color(0x3C3836),
                    text: Self.color(0xEBDBB2),
                    dim: Self.color(0xEBDBB2, opacity: 0.55),
                    accent: Self.color(0xFE8019),
                    success: Self.color(0xB8BB26)
                )
            }
            return PillTheme(
                chip: Self.color(0xFBF1C7),
                surface: Self.color(0xEBDBB2),
                border: Self.color(0xD5C4A1),
                text: Self.color(0x3C3836),
                dim: Self.color(0x3C3836, opacity: 0.55),
                accent: Self.color(0xAF3A03),
                success: Self.color(0x79740E)
            )

        case .tokyonight:
            if colorScheme == .dark {
                return PillTheme(
                    chip: Self.color(0x1A1B26),
                    surface: Self.color(0x292E42),
                    border: Self.color(0x292E42),
                    text: Self.color(0xC0CAF5),
                    dim: Self.color(0xC0CAF5, opacity: 0.50),
                    accent: Self.color(0x7AA2F7),
                    success: Self.color(0x9ECE6A)
                )
            }
            return PillTheme(
                chip: Self.color(0xE1E2E7),
                surface: Self.color(0xC4C8DA),
                border: Self.color(0xC4C8DA),
                text: Self.color(0x3760BF),
                dim: Self.color(0x3760BF, opacity: 0.55),
                accent: Self.color(0x2E7DE9),
                success: Self.color(0x587539)
            )

        case .rosepine:
            if colorScheme == .dark {
                return PillTheme(
                    chip: Self.color(0x191724),
                    surface: Self.color(0x26233A),
                    border: Self.color(0x26233A),
                    text: Self.color(0xE0DEF4),
                    dim: Self.color(0xE0DEF4, opacity: 0.50),
                    accent: Self.color(0xC4A7E7),
                    success: Self.color(0x9CCFD8)
                )
            }
            return PillTheme(
                chip: Self.color(0xFAF4ED),
                surface: Self.color(0xF4EDE8),
                border: Self.color(0xDFDAD9),
                text: Self.color(0x575279),
                dim: Self.color(0x575279, opacity: 0.55),
                accent: Self.color(0x907AA9),
                success: Self.color(0x56949F)
            )
        }
    }

    private static func color(_ hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }
}

private struct MarkerThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = PillThemeChoice.ink.theme(for: .dark)
}

extension EnvironmentValues {
    var markerTheme: PillTheme {
        get { self[MarkerThemeEnvironmentKey.self] }
        set { self[MarkerThemeEnvironmentKey.self] = newValue }
    }
}

private struct MarkerThemeModifier: ViewModifier {
    @AppStorage("pillTheme") private var storedTheme = PillThemeChoice.ink.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var choice: PillThemeChoice {
        PillThemeChoice(rawValue: storedTheme) ?? .ink
    }

    func body(content: Content) -> some View {
        let theme = choice.theme(for: colorScheme)
        content
            .environment(\.markerTheme, theme)
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            .preferredColorScheme(choice.preferredColorScheme)
    }
}

extension View {
    /// Installs the persisted palette at a window or panel root. Keeping this
    /// at the hosting boundary makes a theme change propagate live through
    /// every view in that surface.
    func markerThemed() -> some View {
        modifier(MarkerThemeModifier())
    }
}
