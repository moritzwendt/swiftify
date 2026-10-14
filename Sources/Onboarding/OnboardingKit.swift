import SwiftUI

enum OnboardingPalette {
    static let surface = Color.black.opacity(0.94)
    static let surfaceTint = Color.white.opacity(0.05)
    static let field = Color.black.opacity(0.95)
    static let stroke = Color.white.opacity(0.11)
}

extension View {
    func onboardingSurface(cornerRadius: CGFloat, stroke: Color = OnboardingPalette.stroke) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(OnboardingPalette.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(OnboardingPalette.surfaceTint)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(stroke)
        }
    }

    func onboardingField(focused: Bool = false) -> some View {
        self
            .font(.system(size: 17))
            .foregroundStyle(.white)
            .tint(.white)
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(OnboardingPalette.field, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(focused ? 0.34 : 0.14), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.18), value: focused)
    }
}

struct OnboardingPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 56
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(.white.opacity(isEnabled ? 1 : 0.28), in: .rect(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct OnboardingOutlineButtonStyle: ButtonStyle {
    var height: CGFloat = 56

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .onboardingSurface(cornerRadius: 18, stroke: .white.opacity(0.16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

struct OnboardingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .compositingGroup()
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct OnboardingScaffold<Content: View, Actions: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    let title: String
    let banner: String?
    @ViewBuilder let content: Content
    @ViewBuilder let actions: Actions

    init(
        title: String,
        banner: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.banner = banner
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 0) {
            if let banner {
                OnboardingBanner(message: banner)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }

            Text(title)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 18)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 14)

            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.bottom, 10)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared || reduceMotion ? 0 : 14)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 10) {
                actions
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .opacity(appeared ? 1 : 0)
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: banner)
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)) {
                appeared = true
            }
        }
    }
}

struct OnboardingGlassCircleButton: View {
    let symbol: String
    var diameter: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(.white)
    }
}

struct OnboardingPageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(.white.opacity(position == index ? 1 : 0.25))
                    .frame(width: position == index ? 18 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.3), value: index)
        .accessibilityHidden(true)
    }
}

struct OnboardingBanner: View {
    let message: String
    var tint: Color = .red

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 17))
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.92), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.28)))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}

struct OnboardingCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity)
            .onboardingSurface(cornerRadius: 22)
    }
}

struct OnboardingHero: View {
    @Environment(AppSettings.self) private var settings
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 38, weight: .semibold))
            .foregroundStyle(settings.onAccent)
            .frame(width: 88, height: 88)
            .background(settings.accent.gradient, in: .rect(cornerRadius: 26, style: .continuous))
            .shadow(color: settings.accent.opacity(0.35), radius: 24, y: 10)
            .padding(.vertical, 10)
            .animation(.smooth(duration: 0.3), value: settings.accentHex)
            .accessibilityHidden(true)
    }
}

struct OnboardingDivider: View {
    var inset: CGFloat = 58

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

struct OnboardingInfoRow: View {
    let symbol: String
    let color: Color
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail {
                    Text(detail)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct OnboardingToggleRow: View {
    @Environment(AppSettings.self) private var settings
    let title: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: symbol, color: color)
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(settings.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .haptic(.selection, trigger: isOn)
    }
}

struct OnboardingFormRow: View {
    let label: String
    let value: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 17, weight: emphasized ? .semibold : .regular))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
}

struct OnboardingCopyRow: View {
    @Environment(AppSettings.self) private var settings
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.leading)
                    Text(value)
                        .font(.system(size: 17, design: .monospaced))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(copied ? settings.accent : .white.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(OnboardingPressStyle())
        .animation(.smooth(duration: 0.2), value: copied)
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied && settings.haptics }
    }
}

struct OnboardingChoiceCard: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? Color.white : OnboardingPalette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.clear : OnboardingPalette.stroke)
            }
        }
        .buttonStyle(OnboardingPressStyle())
        .animation(.smooth(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OnboardingChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Color.black : Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.08))
                }
        }
        .buttonStyle(OnboardingPressStyle())
        .animation(.smooth(duration: 0.25), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OnboardingThemePreview: View {
    let scheme: ColorScheme
    let accent: Color

    private var isDark: Bool { scheme == .dark }
    private var background: Color { isDark ? .black : .white }
    private var foreground: Color { isDark ? .white : .black }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Good evening")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground)
                Spacer()
                Circle().fill(accent).frame(width: 28, height: 28)
            }

            HStack(spacing: 10) {
                tile(symbol: "heart.fill", title: "Liked Songs", filled: true)
                tile(symbol: "music.note", title: "Daily Mix", filled: false)
            }

            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in row }
            }

            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent)
                    .frame(width: 34, height: 34)
                Capsule().fill(foreground.opacity(0.5)).frame(width: 96, height: 8)
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(foreground)
            }
            .padding(8)
            .background(foreground.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .background(background, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.18))
        }
        .animation(.smooth(duration: 0.3), value: scheme)
        .accessibilityHidden(true)
    }

    private func tile(symbol: String, title: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(filled ? Color.white : foreground.opacity(0.7))
                .frame(width: 36, height: 36)
                .background(filled ? accent : foreground.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foreground)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(foreground.opacity(0.08), in: .rect(cornerRadius: 10, style: .continuous))
    }

    private var row: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(foreground.opacity(0.12))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(foreground.opacity(0.7)).frame(width: 130, height: 8)
                Capsule().fill(foreground.opacity(0.25)).frame(width: 84, height: 7)
            }
            Spacer(minLength: 0)
        }
    }
}
