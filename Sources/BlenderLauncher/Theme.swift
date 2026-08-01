import SwiftUI

enum Theme {
    static let accent = Color(red: 0.94, green: 0.46, blue: 0.09)
    static let accentSecondary = Color(red: 0.22, green: 0.55, blue: 0.95)
    static let warning = Color(red: 0.94, green: 0.58, blue: 0.10)
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}
