import SwiftUI
import UIKit

// MARK: - ①変換タブ（HTMLの入力＋設定カードをスマホ縦積みに再構成）
struct ConvertView: View {
    @Environment(OjisanStore.self) private var store
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    inputCard()
                    settingsCard()
                    convertBar
                    samplesCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .ojisanBackground()
            .navigationTitle("🍺 オジサン翻訳機")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("閉じる") { inputFocused = false }
                }
            }
        }
    }

    // MARK: - Binding helpers（NativeApp実績パターン・確実にビルド通る）
    private func bindInput() -> Binding<String> {
        Binding(get: { store.input }, set: { store.input = $0 })
    }
    private func bindTarget() -> Binding<String> {
        Binding(get: { store.options.target }, set: { store.options.target = $0; store.saveSettings() })
    }
    private func bindMe() -> Binding<String> {
        Binding(get: { store.options.me }, set: { store.options.me = $0; store.saveSettings() })
    }
    private func bindTimeMode() -> Binding<OjisanTimeMode> {
        Binding(get: { store.options.timeMode }, set: { store.options.timeMode = $0; store.saveSettings() })
    }
    private func bindKimo() -> Binding<Double> {
        Binding(get: { Double(store.options.kimo) }, set: { store.options.kimo = Int($0.rounded()); store.saveSettings() })
    }
    private func bindEmoji() -> Binding<Double> {
        Binding(get: { Double(store.options.emojiLevel) }, set: { store.options.emojiLevel = Int($0.rounded()); store.saveSettings() })
    }
    private func bindShitago() -> Binding<Double> {
        Binding(get: { Double(store.options.shitago) }, set: { store.options.shitago = Int($0.rounded()); store.saveSettings() })
    }
    private func bindToggle(_ kp: WritableKeyPath<OjisanOptions, Bool>) -> Binding<Bool> {
        Binding(get: { store.options[keyPath: kp] }, set: { store.options[keyPath: kp] = $0; store.saveSettings() })
    }

    // MARK: - ヘッダー
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("累計変換 \(store.totalCount) 回 • 完全無料・登録不要")
                    .font(.caption).bold().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(Capsule())

            Text("普通の文章を、クセ強おじさん構文に一発変換。")
                .font(.title2).bold()
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                statBox("6種", "プリセット")
                statBox("120+", "絵文字パーツ")
                statBox("3案", "同時生成")
                statBox("∞", "ウザさ無限大")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ojisanCard()
    }

    private func statBox(_ b: String, _ s: String) -> some View {
        VStack(spacing: 2) {
            Text(b).font(.headline)
            Text(s).font(.caption2).foregroundStyle(.secondary).bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 入力
    private func inputCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "📝 変換したい文章", desc: "敬語でもタメ口でもOK。1行でも長文でも自動でおじさん化するよぉ〜💌✨")

            TextEditor(text: bindInput())
                .focused($inputFocused)
                .frame(minHeight: 130)
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1.5))
                .font(.body)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("相手の呼び方").font(.caption).bold().foregroundStyle(.secondary)
                    TextField("ゆみちゃん", text: bindTarget())
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("自分の一人称").font(.caption).bold().foregroundStyle(.secondary)
                    TextField("おじさん", text: bindMe())
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("時間帯の挨拶").font(.caption).bold().foregroundStyle(.secondary)
                Picker("時間帯", selection: bindTimeMode()) {
                    ForEach(OjisanTimeMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack(spacing: 8) {
                Button("🗑 クリア") { store.input = ""; OjisanActions.haptic() }
                    .buttonStyle(GhostButtonStyle())
                Button("🎲 例文") {
                    store.input = OjisanData.samples.randomElement() ?? ""
                    OjisanActions.haptic()
                }
                .buttonStyle(GhostButtonStyle())
                Button("📋 貼付") {
                    if let t = UIPasteboard.general.string { store.input = t; store.showToast("貼ったよぉ〜😘💕") }
                }
                .buttonStyle(GhostButtonStyle())
                Spacer()
                Text("\(store.input.count)文字・\(store.input.components(separatedBy: .newlines).count)行")
                    .font(.caption).bold().foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .ojisanCard()
    }

    // MARK: - 設定
    private func settingsCard() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "⚙️ おじさん設定", desc: "プリセット＋微調整でキモさを精密制御できるよぉ〜😎✨")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(OjisanData.presets) { p in
                    Button {
                        store.applyPreset(p.id)
                        OjisanActions.haptic()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline).bold()
                            Text("\(p.desc) • キモ\(p.kimo) 絵\(p.emoji)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(store.options.activePreset == p.id ? OjisanTheme.accent.opacity(0.08) : Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(store.options.activePreset == p.id ? OjisanTheme.accent : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            sliderRow(title: "キモさ・ウザさ", value: bindKimo(), label: OjisanData.kimoText[store.options.kimo])
            sliderRow(title: "絵文字の量", value: bindEmoji(), label: OjisanData.emojiText[store.options.emojiLevel])
            sliderRow(title: "お誘い・下心", value: bindShitago(), label: OjisanData.shitagoText[store.options.shitago])

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                toggleRow(bindToggle(\.useAisatsu), "挨拶を追加")
                toggleRow(bindToggle(\.useHome), "褒め言葉")
                toggleRow(bindToggle(\.useKinkyo), "近況報告")
                toggleRow(bindToggle(\.useOffer), "ご飯のお誘い")
                toggleRow(bindToggle(\.useKaomoji), "顔文字 (^^♪")
                toggleRow(bindToggle(\.useKatakana), "カタカナ化")
                toggleRow(bindToggle(\.useBikuri), "❗️⁉️乱用")
                toggleRow(bindToggle(\.useShime), "追伸・催促")
            }

            Text("使う絵文字セット（タップでON/OFF）").font(.caption).bold().foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(OjisanData.emojiAll, id: \.self) { e in
                    Button(e) {
                        if let i = store.options.emojiEnabled.firstIndex(of: e) {
                            store.options.emojiEnabled.remove(at: i)
                        } else {
                            store.options.emojiEnabled.append(e)
                        }
                        store.saveSettings()
                    }
                    .font(.title3)
                    .padding(6)
                    .background(store.options.emojiEnabled.contains(e) ? OjisanTheme.accent.opacity(0.12) : Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(store.options.emojiEnabled.contains(e) ? OjisanTheme.accent : Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .ojisanCard()
    }

    private func sliderRow(title: String, value: Binding<Double>, label: String) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.subheadline).bold()
                Spacer()
                LevelBadge(text: label)
            }
            Slider(value: value, in: 1...5, step: 1)
                .tint(OjisanTheme.accent)
        }
    }

    private func toggleRow(_ b: Binding<Bool>, _ title: String) -> some View {
        Toggle(title, isOn: b)
            .font(.subheadline).bold()
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .tint(OjisanTheme.accent)
    }

    // MARK: - 変換バー
    private var convertBar: some View {
        VStack(spacing: 10) {
            Button {
                OjisanActions.haptic()
                Task { await store.convert(useGemini: true) }
            } label: {
                HStack {
                    if store.isConverting { ProgressView().tint(.white) }
                    Text(store.isConverting ? "変換中…" : "✨ おじさん化する ✨")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.isConverting)

            HStack {
                Button("🎲 3パターン生成") {
                    Task { await store.convert(useGemini: false) }
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(store.isConverting)
                Spacer()
                Text(store.lastUsedGemini ? "🤖AI仕上げ" : "💪ローカル高速")
                    .font(.caption).bold().foregroundStyle(.secondary)
            }
            Text("AI高精度モード内蔵だよぉ〜😍✨ そのままボタンでOK🙏💕")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(red: 0.1, green: 0.1, blue: 0.12))
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - 例文
    private var samplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "📚 ネタ例文", desc: "タップで入力欄にセット → そのまま変換ボタンだよぉ〜😘🎵")
            FlowLayout(spacing: 8) {
                ForEach(OjisanData.samples, id: \.self) { sm in
                    Button(String(sm.prefix(14)) + "…") {
                        store.input = sm
                        OjisanActions.haptic()
                    }
                    .font(.caption).bold()
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                }
            }
        }
        .padding(16)
        .ojisanCard()
    }
}

// MARK: - 回り込みレイアウト
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var h: CGFloat = 0
        for row in rows { h += row.height + (h > 0 ? spacing : 0) }
        return CGSize(width: proposal.width ?? 0, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (i, size) in row.sizes.enumerated() {
                let idx = row.indices[i]
                subviews[idx].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var indices: [Int]; var sizes: [CGSize]; var height: CGFloat }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? 320
        var rows: [Row] = []
        var curIdx: [Int] = []; var curSizes: [CGSize] = []; var curW: CGFloat = 0; var curH: CGFloat = 0
        for (i, sv) in subviews.enumerated() {
            let size = sv.sizeThatFits(.unspecified)
            if !curIdx.isEmpty && curW + spacing + size.width > maxW {
                rows.append(Row(indices: curIdx, sizes: curSizes, height: curH))
                curIdx = []; curSizes = []; curW = 0; curH = 0
            }
            curIdx.append(i); curSizes.append(size)
            curW += (curIdx.count > 1 ? spacing : 0) + size.width
            curH = max(curH, size.height)
        }
        if !curIdx.isEmpty { rows.append(Row(indices: curIdx, sizes: curSizes, height: curH)) }
        return rows
    }
}
