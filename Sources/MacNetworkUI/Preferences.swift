import SwiftUI

/// App-wide preferences stored in UserDefaults (@AppStorage). Keys live here so every window reads
/// the same values.
enum Prefs {
    static let theme = "theme"
    static let accent = "accent"
    static let onboarded = "onboarded"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    var id: Self { self }
    var title: String { self == .system ? "Multicolor" : rawValue.capitalized }
    /// nil = follow the system accent color.
    var color: Color? {
        switch self {
        case .system: nil
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .graphite: .gray
        }
    }
}

extension View {
    /// Applies the chosen theme and accent to a window's root view.
    func themed(_ theme: AppTheme, _ accent: AccentChoice) -> some View {
        preferredColorScheme(theme.colorScheme)
            .tint(accent.color)
    }
}
