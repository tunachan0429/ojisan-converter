import SwiftUI

// MARK: - 情報（天気・Wikipedia・Web検索・朝のまとめ）
struct InfoView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var cityIndex = 0
    @State private var weatherText = "まだ取得していません。"
    @State private var wikiWord = ""
    @State private var wikiResult = ""
    @State private var webWord = ""
    @State private var briefText = ""
    @State private var briefResult = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section("天気") {
                    Picker("都市", selection: $cityIndex) {
                        ForEach(Presets.cities.indices, id: \.self) { i in
                            Text(Presets.cities[i].name).tag(i)
                        }
                    }
                    Button("取得") {
                        Task {
                            working = true
                            defer { working = false }
                            do {
                                let c = Presets.cities[cityIndex]
                                let w = try await InfoClients.fetchWeather(lat: c.lat, lon: c.lon)
                                weatherText = "現在 \(String(format: "%.1f", w.temp))℃ \(w.japanese)・風速 \(String(format: "%.1f", w.wind))m/s"
                            } catch {
                                weatherText = "取得失敗（ネット確認）。"
                            }
                        }
                    }
                    .disabled(working)
                    Text(weatherText).font(.footnote).foregroundStyle(.secondary)
                }
                Section("Wikipedia") {
                    TextField("言葉を入力", text: $wikiWord)
                        .textInputAutocapitalization(.never)
                    Button("調べる") {
                        Task {
                            let q = wikiWord.trimmingCharacters(in: .whitespaces)
                            guard !q.isEmpty else { return }
                            wikiResult = "検索中…"
                            do {
                                let r = try await InfoClients.fetchWiki(q)
                                wikiResult = "\(r.title)\n\(r.extract)" + (r.url.isEmpty ? "" : "\n\n\(r.url)")
                            } catch {
                                wikiResult = "見つからず。表記を変えてみて。"
                            }
                        }
                    }
                    if !wikiResult.isEmpty {
                        Text(wikiResult).font(.footnote).textSelection(.enabled)
                    }
                }
                Section("Web検索") {
                    Text("深掘りはチャットの「検索する」で直接聞くのがおすすめ。")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("キーワード", text: $webWord)
                    HStack {
                        ForEach([("Google", "google"), ("DuckDuckGo", "duck"), ("YouTube", "youtube"), ("Maps", "maps")], id: \.1) { name, key in
                            Button(name) { openSearch(key) }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("要約プロンプトをコピー") {
                        let q = webWord.isEmpty ? "気になる話題" : webWord
                        UIPasteboard.general.string = "「\(q)」について検索結果の要点を整理して。結論→3つのポイント→おすすめ1つ→注意点の順で高校生向けに。"
                    }
                }
                Section("朝のまとめ") {
                    TextField("今日の予定・気になるニュース", text: $briefText, axis: .vertical)
                        .lineLimit(2...4)
                    Button("まとめ文を作る") {
                        Task {
                            let v = briefText.isEmpty ? "今日の予定なし" : briefText
                            do {
                                briefResult = try await GeminiClient.generateLight(
                                    system: "あなたは朝の秘書。天気・予定・ニュースから今日の一言アドバイスを作る。150字以内。",
                                    userText: "以下からまとめ文を作って:\n\(v)",
                                    apiKey: settings.apiKey)
                            } catch {
                                briefResult = "・予定: \(v)\n・持ち物・遅刻に注意"
                            }
                        }
                    }
                    if !briefResult.isEmpty {
                        Text(briefResult).font(.footnote).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("情報")
        }
    }

    private func openSearch(_ key: String) {
        let q = webWord.trimmingCharacters(in: .whitespaces).isEmpty ? "高校生 おすすめ" : webWord
        let base: String
        switch key {
        case "duck": base = "https://duckduckgo.com/?q="
        case "youtube": base = "https://www.youtube.com/results?search_query="
        case "maps": base = "https://www.google.com/maps/search/"
        default: base = "https://www.google.com/search?q="
        }
        if let url = URL(string: base + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)) {
            UIApplication.shared.open(url)
        }
    }
}
