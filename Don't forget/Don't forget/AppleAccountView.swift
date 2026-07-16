import SwiftUI

struct WelcomeView: View {
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(SettingsKeys.hasCompletedWelcome)
    private var hasCompletedWelcome = false

    @AppStorage(SettingsKeys.iCloudSyncEnabled)
    private var iCloudSyncEnabled = true

    @State private var logoIsFloating = false

    private var subtitle: String {
        locale.localized("Schrijf alles op in de app, zodat je niets hoeft te onthouden.")
    }

    var body: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 720

            ZStack {
                WelcomeBackground()

                VStack(spacing: 0) {
                    Spacer(minLength: compactHeight ? 12 : 30)

                    Image("OnboardingLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: compactHeight ? 154 : 190,
                            height: compactHeight ? 154 : 190
                        )
                        .shadow(color: Color.brandHardBlue.opacity(0.18), radius: 22, y: 10)
                        .scaleEffect(logoIsFloating ? 1.025 : 0.985)
                        .offset(y: logoIsFloating ? -5 : 3)
                        .accessibilityHidden(true)

                    Text(locale.appDisplayName)
                        .font(.system(size: compactHeight ? 36 : 40, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .padding(.top, compactHeight ? 16 : 24)

                    WelcomeSubtitle(text: subtitle, compact: compactHeight)
                        .padding(.top, compactHeight ? 8 : 10)

                    Spacer(minLength: compactHeight ? 14 : 24)

                    controlsCard
                        .adaptiveReadableWidth(maxWidth: 620)
                }
                .padding(.horizontal, compactHeight ? 20 : 24)
                .padding(.bottom, compactHeight ? 14 : 22)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                logoIsFloating = true
            }
        }
    }

    private var controlsCard: some View {
        VStack(spacing: 18) {
            Toggle(isOn: $iCloudSyncEnabled) {
                Label {
                    Text(locale.localized("iCloud-synchronisatie"))
                } icon: {
                    Image(systemName: "icloud.fill")
                        .foregroundStyle(Color.brandHardBlue)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            }
            .tint(.brandHardBlue)
            .padding(.horizontal, 4)
            .onChange(of: iCloudSyncEnabled) { _, enabled in
                if enabled {
                    CloudSettingsSynchronizer.shared.start()
                } else {
                    CloudSettingsSynchronizer.shared.stop()
                }
            }

            Button {
                hasCompletedWelcome = true
            } label: {
                HStack(spacing: 10) {
                    Text(locale.localized("Aan de slag"))
                    Image(systemName: "chevron.forward")
                        .font(.subheadline.weight(.bold))
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
                .background(
                    LinearGradient(
                        colors: [Color.brandHardBlue, Color.brandHardBlue.opacity(0.82)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
                .shadow(color: Color.brandHardBlue.opacity(0.25), radius: 12, y: 7)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .background(
            (colorScheme == .light ? Color.white.opacity(0.84) : Color.black.opacity(0.34)),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    colorScheme == .light ? Color.white.opacity(0.9) : Color.white.opacity(0.14),
                    lineWidth: 1
                )
        }
        .shadow(color: Color.brandHardBlue.opacity(0.10), radius: 24, y: 10)
    }
}

private struct WelcomeSubtitle: View {
    let text: String
    let compact: Bool

    private var wrappedText: String {
        let commaCharacters: Set<Character> = [",", "،", "，", "、"]

        guard let commaIndex = text.firstIndex(where: commaCharacters.contains) else {
            return text
        }

        let lineBreakIndex = text.index(after: commaIndex)
        let firstLine = text[..<lineBreakIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let secondLine = text[lineBreakIndex...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !firstLine.isEmpty, !secondLine.isEmpty else { return text }
        return "\(firstLine)\n\(secondLine)"
    }

    var body: some View {
        Text(wrappedText)
            .font(.system(size: compact ? 19 : 21, weight: .regular, design: .rounded))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .allowsTightening(true)
            .frame(maxWidth: 540)
            .accessibilityLabel(text)
    }
}

private struct WelcomeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            colorScheme == .light ? Color.brandLightGrey : Color(hex: 0x10141C)

            RadialGradient(
                colors: colorScheme == .light
                    ? [Color.white.opacity(0.92), Color.brandLightBlue.opacity(0.48), .clear]
                    : [Color.brandHardBlue.opacity(0.22), Color.brandHardBlue.opacity(0.08), .clear],
                center: .top,
                startRadius: 18,
                endRadius: 440
            )

            Circle()
                .fill(colorScheme == .light ? Color.white.opacity(0.48) : Color.white.opacity(0.035))
                .frame(width: 250, height: 250)
                .blur(radius: 1)
                .offset(x: -150, y: -180)

            Circle()
                .fill(colorScheme == .light
                    ? Color.brandLightBlue.opacity(0.42)
                    : Color.brandHardBlue.opacity(0.14))
                .frame(width: 210, height: 210)
                .blur(radius: 2)
                .offset(x: 155, y: -40)

            decorativeSymbol("sparkles", size: 22, opacity: 0.32)
                .offset(x: 142, y: -168)

            decorativeSymbol("sparkle", size: 15, opacity: 0.23)
                .offset(x: -145, y: -62)

            decorativeSymbol("circle.fill", size: 11, opacity: 0.14)
                .offset(x: 130, y: 92)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func decorativeSymbol(_ name: String, size: CGFloat, opacity: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.brandHardBlue.opacity(opacity))
            .shadow(
                color: colorScheme == .light ? .white.opacity(0.9) : .black.opacity(0.45),
                radius: 5
            )
    }
}
