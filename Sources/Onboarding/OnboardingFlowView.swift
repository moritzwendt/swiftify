import SwiftUI

enum OnboardingStep: Hashable {
    case welcome, dashboard, appSettings, clientID, appearance, layout, cache, signIn
}

enum OnboardingFlow {
    case full, entry

    var steps: [OnboardingStep] {
        switch self {
        case .full: [.dashboard, .appSettings, .clientID, .appearance, .layout, .cache, .signIn]
        case .entry: [.clientID, .appearance, .layout, .cache, .signIn]
        }
    }
}

struct OnboardingFlowView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: OnboardingStep = .welcome
    @State private var flow: OnboardingFlow = .full
    @State private var isForward = true
    @State private var isLeavingWelcome = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [settings.accent.opacity(0.5), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.5), value: settings.accentHex)

            VStack(spacing: 0) {
                header
                GeometryReader { geometry in
                    ZStack {
                        welcomeScreen
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(x: step == .welcome ? 0 : -geometry.size.width)
                            .opacity(step == .welcome ? 1 : 0)
                            .allowsHitTesting(step == .welcome)
                            .accessibilityHidden(step != .welcome)

                        if step != .welcome {
                            currentScreen
                                .id(step)
                                .transition(pageTransition)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .padding(.bottom, 22)
        }
        .preferredColorScheme(.dark)
        .haptic(.impact(weight: .light), trigger: step)
    }

    private var header: some View {
        ZStack {
            HStack {
                OnboardingGlassCircleButton(symbol: "chevron.left", action: goBack)
                    .opacity(step == .welcome ? 0 : 1)
                    .disabled(step == .welcome)
                    .accessibilityLabel("Back")
                Spacer()
            }
            if step != .welcome, flow.steps.count > 1, let index = flow.steps.firstIndex(of: step) {
                OnboardingPageDots(count: flow.steps.count, index: index)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .frame(height: 46, alignment: .top)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private var welcomeScreen: some View {
        OnboardingWelcomeScreen(
            isLeaving: $isLeavingWelcome,
            onSetup: { start(.full) },
            onEnterID: { start(.entry) }
        )
    }

    @ViewBuilder private var currentScreen: some View {
        switch step {
        case .welcome:
            EmptyView()
        case .dashboard:
            OnboardingDashboardScreen(onContinue: next)
        case .appSettings:
            OnboardingAppSettingsScreen(onContinue: next)
        case .clientID:
            OnboardingClientIDScreen(showsRedirect: flow != .full, onContinue: next)
        case .appearance:
            OnboardingAppearanceScreen(onContinue: next)
        case .layout:
            OnboardingLayoutScreen(onContinue: next)
        case .cache:
            OnboardingCacheScreen(onContinue: next)
        case .signIn:
            OnboardingSignInScreen()
        }
    }

    private var pageAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.22) : .smooth(duration: 0.38)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func start(_ newFlow: OnboardingFlow) {
        flow = newFlow
        advance(to: newFlow.steps[0])
    }

    private func next() {
        guard let index = flow.steps.firstIndex(of: step) else { return }
        if index + 1 < flow.steps.count {
            advance(to: flow.steps[index + 1])
        } else {
            goBackToWelcome()
        }
    }

    private func advance(to next: OnboardingStep) {
        isForward = true
        withAnimation(pageAnimation) { step = next }
    }

    private func goBack() {
        guard step != .welcome else { return }
        isForward = false
        let index = flow.steps.firstIndex(of: step) ?? 0
        let previous = index > 0 ? flow.steps[index - 1] : OnboardingStep.welcome
        withAnimation(pageAnimation) {
            if previous == .welcome { isLeavingWelcome = false }
            step = previous
        }
    }

    private func goBackToWelcome() {
        isForward = false
        withAnimation(pageAnimation) {
            isLeavingWelcome = false
            step = .welcome
        }
    }
}

private struct OnboardingWelcomeScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isLeaving: Bool
    let onSetup: () -> Void
    let onEnterID: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Text("Swiftify")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .tracking(-1.5)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .opacity(appeared && !isLeaving ? 1 : 0)
                .offset(y: appeared ? 0 : 14)

            Spacer(minLength: 12)
            Spacer(minLength: 12)

            VStack(spacing: 6) {
                Button("Set up Client ID") { leave(using: onSetup) }
                    .buttonStyle(OnboardingPrimaryButtonStyle())

                footerLink(question: "Already have a Client ID?", action: "Enter it here") {
                    leave(using: onEnterID)
                }
            }
            .padding(.horizontal, 22)
            .opacity(appeared && !isLeaving ? 1 : 0)
            .allowsHitTesting(!isLeaving)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.55)) {
                appeared = true
            }
        }
    }

    private func footerLink(question: String, action: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(question)
                    .foregroundStyle(.white.opacity(0.5))
                Text(action)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .font(.system(size: 14))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
    }

    private func leave(using action: @escaping () -> Void) {
        guard !isLeaving else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.38)) {
            isLeaving = true
        }
        let delay = reduceMotion ? 0.04 : 0.11
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            action()
        }
    }
}
