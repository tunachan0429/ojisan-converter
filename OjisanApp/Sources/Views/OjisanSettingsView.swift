import SwiftUI

// MARK: - ⑤設定タブ（API埋め込み表示＋外観＋例文＋使い方＋FAQ＋データ管理）
struct OjisanSettingsView: View {
    @Environment(OjisanStore.self) private var store
    @State private var keyMsg = ""
    @State private var showWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("🤖 Gemini AI 高精度モード") {
                    Text("埋め込みキー優先。空なら下の欄・ローカル変換で動作するよぉ〜💪😘").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Text("状態").font(.caption).bold().foregroundStyle(.secondary)
                        Spacer()
                        Text(store.keyStatusText).font(.caption).bold()
                    }
                    SecureField("AIza…（上書き用・任意）", text: Binding(get: { store.apiKeyOverride }, set: { store.apiKeyOverride = $0; store.saveSettings() }))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("モデル", selection: Binding(get: { store.geminiModel }, set: { store.geminiModel = $0; store.saveSettings() })) {
                        ForEach(OjisanConfig.geminiModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    HStack {
                        Button("接続テスト") {
                            Task {
                                keyMsg = "テスト中…"
                                keyMsg = await store.testConnection()
                            }
                        }
                        .disabled(store.effectiveKey.isEmpty)
                        Button("上書き削除", role: .destructive) {
                            store.apiKeyOverride = ""
                            store.saveSettings()
                            keyMsg = ""
                        }
                    }
                    if !keyMsg.isEmpty {
                        Text(keyMsg).font(.caption).foregroundStyle(.secondary)
                    }
                    Link("キーの取得はこちら（無料）", destination: URL(string: OjisanConfig.keyDocURL)!)
                        .font(.caption)
                }

                Section("🎨 外観（ダークモード対応：今回の追加機能）") {
                    Picker("テーマ", selection: Binding(get: { store.appearance }, set: { store.appearance = $0; store.saveSettings() })) {
                        ForEach(OjisanAppearance.allCases, id: \.self) { a in Text(a.label).tag(a) }
                    }
                    .pickerStyle(.segmented)
                    Text("「システム連動」にするとiPhoneの設定に自動で追従するよぉ〜🌃✨").font(.caption).foregroundStyle(.secondary)
                }

                Section("📚 ネタ例文ギャラリー") {
                    ForEach(OjisanData.samples, id: \.self) { sm in
                        Button {
                            store.input = sm
                            store.selectedTab = 0
                            store.showToast("セットしたよぉ〜😘💕")
                        } label: {
                            Text(sm).font(.callout).lineLimit(2)
                        }
                    }
                }

                Section("📖 使い方") {
                    howRow("① ✍️", "文章を入れる", "業務連絡・誘い・謝罪なんでもOK。相手の名前で密着感爆上がり😍💕")
                    howRow("② 🎚️", "キモさを盛る", "プリセット6種＋スライダー＋絵文字で微調整🍺✨")
                    howRow("③ 📤", "送って笑いを取る", "結果タブからコピー・共有・読み上げ対応‼️😘")
                }

                Section("❓ よくある質問") {
                    DisclosureGroup("絵文字が多すぎて読みにくいのですが？") {
                        Text("それが魅力だよぉ〜😍💕 変換タブの「絵文字の量」を1〜2に下げるとマイルドになるよぉ〜🙏✨").font(.callout)
                    }
                    DisclosureGroup("Geminiなしでも精度は低いの？") {
                        Text("いいえ😎✨ ローカルエンジンが挨拶・褒め・近況・お誘い・追伸・語尾・カタカナ・顔文字を完全再現。オフラインでも十分キモいよぉ〜💪💕").font(.callout)
                    }
                    DisclosureGroup("実際に送っても大丈夫？") {
                        Text("仲の良い相手のネタ専用にしてねぇ〜🥺💦 目上の人・業務相手には絶対ダメだよぉ〜🙏‼️").font(.callout)
                    }
                }

                Section("📊 利用状況・データ") {
                    HStack {
                        Text("累計変換")
                        Spacer()
                        Text("\(store.totalCount) 回").bold()
                    }
                    HStack {
                        Text("履歴")
                        Spacer()
                        Text("\(store.history.count) 件（上限500）").foregroundStyle(.secondary)
                    }
                    Button("履歴を全部消す", role: .destructive) { showWipe = true }
                    Button("設定を初期化") {
                        store.options = OjisanOptions()
                        store.saveSettings()
                        store.showToast("初期化したよぉ〜🙏✨")
                    }
                }

                Section("このアプリについて") {
                    Text("オジサン翻訳機 🍺 ネタツール。SwiftUI完全ネイティブ・オフライン可。データはこのiPhoneにだけ保存。APIキーは埋め込み優先＋設定で上書き可。Bundle: \(OjisanConfig.bundleID)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定 ⚙️")
            .confirmationDialog("履歴を消しますか？", isPresented: $showWipe, titleVisibility: .visible) {
                Button("消す", role: .destructive) { store.clearHistory() }
                Button("やめる", role: .cancel) {}
            }
        }
    }

    private func howRow(_ ico: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(ico).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
