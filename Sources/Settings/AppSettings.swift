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

enum TopArtistsRange: String, CaseIterable, Identifiable {
    case shortTerm = "short_term"
    case mediumTerm = "medium_term"
    case longTerm = "long_term"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortTerm: "Last 4 weeks"
        case .mediumTerm: "Last 6 months"
        case .longTerm: "All time"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private static let defaults = UserDefaults.standard

    var appearance: AppearanceMode {
        didSet { Self.defaults.set(appearance.rawValue, forKey: "settings.appearance") }
    }

    var accentHex: String {
        didSet { Self.defaults.set(accentHex, forKey: "settings.accentHex") }
    }

    var dynamicPlayerBackground: Bool {
        didSet { Self.defaults.set(dynamicPlayerBackground, forKey: "settings.dynamicPlayerBackground") }
    }

    var squareArtwork: Bool {
        didSet { Self.defaults.set(squareArtwork, forKey: "settings.squareArtwork") }
    }

    var tabBarMinimizes: Bool {
        didSet { Self.defaults.set(tabBarMinimizes, forKey: "settings.tabBarMinimizes") }
    }

    var haptics: Bool {
        didSet { Self.defaults.set(haptics, forKey: "settings.haptics") }
    }

    var showExplicitBadge: Bool {
        didSet { Self.defaults.set(showExplicitBadge, forKey: "settings.showExplicitBadge") }
    }

    var homeShowRecent: Bool {
        didSet { Self.defaults.set(homeShowRecent, forKey: "settings.homeShowRecent") }
    }

    var homeShowTopArtists: Bool {
        didSet { Self.defaults.set(homeShowTopArtists, forKey: "settings.homeShowTopArtists") }
    }

    var homeQuickCount: Int {
        didSet { Self.defaults.set(homeQuickCount, forKey: "settings.homeQuickCount") }
    }

    var topArtistsRange: TopArtistsRange {
        didSet { Self.defaults.set(topArtistsRange.rawValue, forKey: "settings.topArtistsRange") }
    }

    var librarySortRaw: String {
        didSet { Self.defaults.set(librarySortRaw, forKey: "settings.librarySort") }
    }

    var libraryGrid: Bool {
        didSet { Self.defaults.set(libraryGrid, forKey: "settings.libraryGrid") }
    }

    var showLikedSongsRow: Bool {
        didSet { Self.defaults.set(showLikedSongsRow, forKey: "settings.showLikedSongsRow") }
    }

    var previousRestartSeconds: Int {
        didSet { Self.defaults.set(previousRestartSeconds, forKey: "settings.previousRestartSeconds") }
    }

    var cacheLists: Bool {
        didSet { Self.defaults.set(cacheLists, forKey: "settings.cacheLists") }
    }

    var cacheImages: Bool {
        didSet { Self.defaults.set(cacheImages, forKey: "settings.cacheImages") }
    }

    var preferredDeviceID: String? {
        didSet { Self.defaults.set(preferredDeviceID, forKey: "settings.preferredDeviceID") }
    }

    var preferredDeviceName: String? {
        didSet { Self.defaults.set(preferredDeviceName, forKey: "settings.preferredDeviceName") }
    }

    init() {
        let defaults = Self.defaults
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "settings.appearance") ?? "") ?? .system
        accentHex = defaults.string(forKey: "settings.accentHex") ?? AccentPreset.all[0].hex
        dynamicPlayerBackground = defaults.object(forKey: "settings.dynamicPlayerBackground") as? Bool ?? true
        squareArtwork = defaults.object(forKey: "settings.squareArtwork") as? Bool ?? false
        tabBarMinimizes = defaults.object(forKey: "settings.tabBarMinimizes") as? Bool ?? true
        haptics = defaults.object(forKey: "settings.haptics") as? Bool ?? true
        showExplicitBadge = defaults.object(forKey: "settings.showExplicitBadge") as? Bool ?? true
        homeShowRecent = defaults.object(forKey: "settings.homeShowRecent") as? Bool ?? true
        homeShowTopArtists = defaults.object(forKey: "settings.homeShowTopArtists") as? Bool ?? true
        homeQuickCount = defaults.object(forKey: "settings.homeQuickCount") as? Int ?? 6
        topArtistsRange = TopArtistsRange(rawValue: defaults.string(forKey: "settings.topArtistsRange") ?? "") ?? .mediumTerm
        librarySortRaw = defaults.string(forKey: "settings.librarySort") ?? "Recents"
        libraryGrid = defaults.object(forKey: "settings.libraryGrid") as? Bool ?? false
        showLikedSongsRow = defaults.object(forKey: "settings.showLikedSongsRow") as? Bool ?? true
        previousRestartSeconds = defaults.object(forKey: "settings.previousRestartSeconds") as? Int ?? 3
        cacheLists = defaults.object(forKey: "settings.cacheLists") as? Bool ?? true
        cacheImages = defaults.object(forKey: "settings.cacheImages") as? Bool ?? true
        preferredDeviceID = defaults.string(forKey: "settings.preferredDeviceID")
        preferredDeviceName = defaults.string(forKey: "settings.preferredDeviceName")
    }

    var accent: Color { Color(hex: accentHex) }

    var onAccent: Color { accent.isLight ? .black : .white }

    func reset() {
        appearance = .system
        accentHex = AccentPreset.all[0].hex
        dynamicPlayerBackground = true
        squareArtwork = false
        tabBarMinimizes = true
        haptics = true
        showExplicitBadge = true
        homeShowRecent = true
        homeShowTopArtists = true
        homeQuickCount = 6
        topArtistsRange = .mediumTerm
        librarySortRaw = "Recents"
        libraryGrid = false
        showLikedSongsRow = true
        previousRestartSeconds = 3
        cacheLists = true
        cacheImages = true
        preferredDeviceID = nil
        preferredDeviceName = nil
    }
}
