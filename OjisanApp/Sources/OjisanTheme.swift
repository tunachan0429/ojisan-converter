import SwiftUI

// MARK: - HTML見た目の移植（スマホ用タブUI＋ダークモード対応）
// ライト時はHTMLそのまま (#f6f5f1 / #ff4d6d→#ff8a3d)。ダーク時は目に優しく反転。
enum OjisanTheme {
    static let accent = Color(red: 1.0, green: 0.30, blue: 0.43)      // #ff4d6d
    static let accent2 = Color(red: 1.0, green: 0.54, blue: 0.24)     // #ff8a3d
    static let accentGradient = LinearGradient(
        colors: [accent, accent2],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let scoreGradient = LinearGradient(
        colors: [Color(red: 1, green: 0.82, blue: 0.4), accent2, accent],
        startPoint: .leading, endPoint: .trailing
    )
}

struct OjisanCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .background(scheme == .dark ? Color(red: 0.13, green: 0.13, blue: 0.15) : .white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(scheme == .dark ? Color.white.opacity(0.08) : Color(red: 0.93, green: 0.91, blue: 0.89), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 12, y: 6)
    }
}

extension View {
    func ojisanCard() -> some View { modifier(OjisanCard()) }

    func ojisanBackground() -> some View {
        modifier(OjisanBackground())
    }
}

struct OjisanBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(
            scheme == .dark
                ? Color(red: 0.07, green: 0.07, blue: 0.09)
                : Color(red: 0.965, green: 0.96, blue: 0.945)
        )
    }
}

// MARK: - 共通パーツ
struct SectionHeader: View {
    let title: String
    let desc: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LevelBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(Color.primary.opacity(0.07))
            .clipShape(Capsule())
    }
}

struct HotBadge: View {
    let text: String
    var hot: Bool = false
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(backgroundView)
            .foregroundStyle(hot ? Color.white : Color.primary)
            .clipShape(Capsule())
    }
    @ViewBuilder
    private var backgroundView: some View {
        if hot {
            OjisanTheme.accentGradient
        } else {
            Color.primary.opacity(0.07)
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 26).padding(.vertical, 13)
            .background(OjisanTheme.accentGradient.opacity(isEnabled ? 1 : 0.5))
            .clipShape(Capsule())
            .shadow(color: OjisanTheme.accent.opacity(0.3), radius: isEnabled ? 10 : 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline).bold()
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(scheme == .dark ? Color.white.opacity(0.08) : .white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
