import Observation
import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AccentPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }

    static let all: [AccentPreset] = [
        AccentPreset(name: "Green", hex: "1ED760"),
        AccentPreset(name: "Blue", hex: "0A84FF"),
        AccentPreset(name: "Purple", hex: "AF52DE"),
        AccentPreset(name: "Pink", hex: "FF2D55"),
        AccentPreset(name: "Red", hex: "FF3B30"),
        AccentPreset(name: "Orange", hex: "FF9500"),
        AccentPreset(name: "Yellow", hex: "FFCC00"),
        AccentPreset(name: "Teal", hex: "30B0C7")
    ]
}

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var isLight: Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return 0.299 * red + 0.587 * green + 0.114 * blue > 0.6
    }
}

@MainActor
@Observable
final class AppSettings {
    var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "settings.appearance") }
    }

    var accentHex: String {
        didSet { UserDefaults.standard.set(accentHex, forKey: "settings.accentHex") }
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "settings.appearance") ?? "") ?? .system
        accentHex = defaults.string(forKey: "settings.accentHex") ?? AccentPreset.all[0].hex
    }

    var accent: Color { Color(hex: accentHex) }

    var onAccent: Color { accent.isLight ? .black : .white }
}
