import SwiftUI
import AVFoundation
import UIKit

@main
struct OjisanApp: App {
    @State private var store: OjisanStore

    init() {
        _store = State(initialValue: OjisanStore())
    }

    var body: some Scene {
        WindowGroup {
            OjisanContentView()
                .environment(store)
                .preferredColorScheme(colorScheme(for: store.appearance))
        }
    }

    private func colorScheme(for a: OjisanAppearance) -> ColorScheme? {
        switch a {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct OjisanContentView: View {
    @Environment(OjisanStore.self) private var store

    var body: some View {
        TabView(selection: Binding(get: { store.selectedTab }, set: { store.selectedTab = $0 })) {
            ConvertView()
                .tabItem { Label("変換", systemImage: "wand.and.stars") }
                .tag(0)
            ResultView()
                .tabItem { Label("結果", systemImage: "doc.on.doc") }
                .tag(1)
            LinePreviewView()
                .tabItem { Label("LINE", systemImage: "message.fill") }
                .tag(2)
            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock") }
                .tag(3)
            OjisanSettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(4)
        }
        .overlay(alignment: .bottom) {
            if !store.toast.isEmpty {
                Text(store.toast)
                    .font(.subheadline).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 11)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .clipShape(Capsule())
                    .shadow(radius: 12)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        let msg = store.toast
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_200_000_000)
                            if store.toast == msg { store.toast = "" }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.25), value: store.toast)
    }
}

// MARK: - 共有・読み上げ・コピー共通
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

enum OjisanActions {
    private static var synthesizer = AVSpeechSynthesizer()

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }

    static func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = 0.52
        synthesizer.speak(u)
    }

    static func haptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
