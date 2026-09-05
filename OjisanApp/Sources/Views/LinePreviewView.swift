import SwiftUI

// MARK: - ③LINEプレビュータブ（HTMLのphone＋キモさ分析レポートを分離）
struct LinePreviewView: View {
    @Environment(OjisanStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    reportCard
                    phoneCard
                }
                .padding(16)
            }
            .ojisanBackground()
            .navigationTitle("LINE・分析 📊")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "📊 キモさ分析レポート", desc: "絵文字密度・語尾・ウザ要素を自動採点するよぉ〜😎‼️")
            if let rep = store.lastReport, !store.lastConvertedText.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(rep.score)").font(.system(size: 34, weight: .bold))
                    Text("/ 100点・\(rep.rank)").font(.subheadline).bold()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1)).frame(height: 10)
                        OjisanTheme.scoreGradient
                            .clipShape(Capsule())
                            .frame(width: geo.size.width * CGFloat(rep.score) / 100, height: 10)
                    }
                }
                .frame(height: 10)
                HStack(spacing: 6) {
                    Text("❤️ 絵文字 \(rep.emojiCount)個")
                    Text("•")
                    Text("(^^♪ \(rep.kaoCount)個")
                    Text("•")
                    Text("📝 \(store.lastConvertedText.count)文字")
                }
                .font(.caption).bold().foregroundStyle(.secondary)
                Text(rep.score >= 70 ? "完璧だよぉ〜😍💕このまま送ったらブロックされちゃうかもぉ〜(^_^;)💦" : "もっと盛りたいなら絵文字LvとキモさLvを上げてみてねぇ〜💪😘✨")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("🎭 \(store.options.activePreset)")
                    Spacer()
                    Text(store.lastUsedGemini ? "🤖 AI併用" : "💪 ローカル")
                }
                .font(.caption2).bold().foregroundStyle(.secondary)
            } else {
                Text("まだ変換してないよぉ〜🥺早く変換してみてねぇ〜💕")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                Button("変換タブへ") { store.selectedTab = 0 }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(16)
        .ojisanCard()
    }

    private var phoneCard: some View {
        VStack(spacing: 0) {
            // 本体
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("＜").bold()
                    Text("\(store.options.target.isEmpty ? "ゆみちゃん" : store.options.target) 💕").bold()
                    Spacer()
                    Text("🔍 📞 ☰")
                }
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color(red: 0.18, green: 0.23, blue: 0.27))

                VStack(alignment: .leading, spacing: 10) {
                    if store.lastConvertedText.isEmpty {
                        bubble("ここにLINE風プレビューが出るよぉ〜😍💕", time: "既読 12:34")
                    } else {
                        let parts = store.lastConvertedText.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(4)
                        ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                            bubble(p, time: "既読 12:3\(i)")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(LinearGradient(colors: [Color(red: 0.6, green: 0.7, blue: 0.83), Color(red: 0.56, green: 0.66, blue: 0.79)], startPoint: .top, endPoint: .bottom))

                HStack(spacing: 8) {
                    Text("メッセージを入力…")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                    Text("😍").font(.title3)
                }
                .padding(10)
                .background(Color.white)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .padding(12)
        .background(Color(red: 0.06, green: 0.08, blue: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .shadow(radius: 10)
    }

    private func bubble(_ text: String, time: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.callout).lineSpacing(4).foregroundStyle(.black)
            Text(time).font(.caption2).foregroundStyle(.black.opacity(0.5))
        }
        .padding(10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}
