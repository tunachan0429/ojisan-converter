import SwiftUI
import UIKit

// MARK: - ②結果タブ（HTMLのresults＋コピー/X/LINE/Discord/読み上げをiOS共有シート対応に強化）
struct ResultView: View {
    @Environment(OjisanStore.self) private var store
    @State private var shareText = ""
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.results.isEmpty {
                        emptyCard
                    } else {
                        ForEach(store.results) { r in
                            resultCard(r)
                        }
                    }
                }
                .padding(16)
            }
            .ojisanBackground()
            .navigationTitle("結果 🎭 \(store.options.activePreset)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.results.isEmpty {
                    Button("全部コピー") {
                        OjisanActions.copy(store.results.map { $0.text }.joined(separator: "\n\n---\n\n"))
                        store.showToast("全部コピーしたよぉ〜😍💕")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [shareText])
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Text("📭").font(.largeTitle)
            Text("まだ変換してないよぉ〜🥺").bold()
            Text("「変換」タブで文章を入れてボタンを押してねぇ〜💕").font(.caption).foregroundStyle(.secondary)
            Button("変換タブへ") { store.selectedTab = 0 }
                .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .ojisanCard()
    }

    private func resultCard(_ r: OjisanResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(r.title).font(.subheadline).bold()
                HotBadge(text: r.badge, hot: r.isHot)
                Spacer()
                Text("\(r.text.count)文字").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            Text(r.text)
                .font(.body)
                .lineSpacing(6)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02))
                .textSelection(.enabled)
            Divider()
            FlowLayout(spacing: 8) {
                Button("📋 コピー") {
                    OjisanActions.copy(r.text)
                    store.showToast("コピーしたよぉ〜😍💕")
                }.buttonStyle(GhostButtonStyle())
                Button("📤 共有") {
                    shareText = r.text
                    showShare = true
                }.buttonStyle(GhostButtonStyle())
                Button("𝕏 投稿") {
                    let t = String(r.text.prefix(130)) + "… #オジサン翻訳機"
                    if let u = URL(string: "https://twitter.com/intent/tweet?text=" + (t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                        UIApplication.shared.open(u)
                    }
                }.buttonStyle(GhostButtonStyle())
                Button("💬 LINE") {
                    if let u = URL(string: "https://line.me/R/share?text=" + (r.text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                        UIApplication.shared.open(u)
                    }
                }.buttonStyle(GhostButtonStyle())
                Button("🔊 読む") {
                    OjisanActions.speak(r.text)
                    store.showToast("読み上げるよぉ〜🎵😘")
                }.buttonStyle(GhostButtonStyle())
            }
            .padding(12)
        }
        .ojisanCard()
    }
}
