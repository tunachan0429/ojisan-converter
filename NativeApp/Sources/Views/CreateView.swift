import SwiftUI

// MARK: - 作成（連絡文・ アイデア）
struct CreateView: View {
    @Environment(SettingsStore.self) private var settings

    @State private var templateID = "bukatu"
    @State private var to = "顧問の先生"
    @State private var from = "1年"
    @State private var body_ = ""
    @State private var tone = "丁寧"
    @State private var contactOut = ""
    @State private var ideaIn = ""
    @State private var ideaOut = ""
    @State private var working = false

    let tones = ["丁寧", "カジュアル丁寧", "短め"]

    var body: some View {
        NavigationStack {
            Form {
                Section("連絡文") {
                    Picker("種類", selection: $templateID) {
                        ForEach(Presets.contactTemplates) { t in
                            Text(t.name).tag(t.id)
                        }
                    }
                    TextField("相手", text: $to)
                    TextField("自分", text: $from)
                    TextField("用件", text: $body_)
                    Picker("トーン", selection: $tone) {
                        ForEach(tones, id: \.self) { Text($0).tag($0) }
                    }
                    Button("連絡文を作る") {
                        Task {
                            working = true
                            defer { working = false }
                            let tpl = Presets.contactTemplates.first(where: { $0.id == templateID })?.name ?? ""
                            do {
                                contactOut = try await GeminiClient.generateLight(
                                    system: "あなたは連絡文のプロ。",
                                    userText: "連絡文を作って。種類:\(tpl) 相手:\(to) 自分:\(from) 用件:\(body_) トーン:\(tone)。丁寧文と短文LINE用の2案。",
                                    apiKey: settings.apiKey)
                            } catch {
                                contactOut = offlineContact()
                            }
                        }
                    }
                    .disabled(working)
                    .buttonStyle(.borderedProminent)
                    if !contactOut.isEmpty {
                        Text(contactOut).font(.footnote).textSelection(.enabled)
                        HStack {
                            Button("コピー") {
                                UIPasteboard.general.string = contactOut
                            }
                            Button("LINEで送る") {
                                if let url = URL(string: "https://line.me/R/share?text=\(contactOut.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                Section("アイデア・投稿文") {
                    TextField("テーマ", text: $ideaIn)
                    HStack {
                        Button("10案出す") {
                            Task {
                                let v = ideaIn.isEmpty ? "週末の遊び" : ideaIn
                                do {
                                    ideaOut = try await GeminiClient.generateLight(
                                        system: "あなたは企画マン。10案を箇条書きで。",
                                        userText: "\(v)について面白い案10個出して。高校生向け。",
                                        apiKey: settings.apiKey)
                                } catch {
                                    ideaOut = "【10案（オフライン）】 \(v)\n1. 定番 2. 限定 3. コラボ 4. ランキング 5. 体験型 6. SNS連動 7. 夜企画 8. 初心者枠 9. ガチ枠 10. ネタ枠"
                                }
                            }
                        }
                        Button("SNS文にする") {
                            Task {
                                let v = ideaIn.isEmpty ? "今日の出来事" : ideaIn
                                do {
                                    ideaOut = try await GeminiClient.generateLight(
                                        system: "あなたはSNS運用者。140字以内の投稿文＋ハッシュタグ3つを作る。",
                                        userText: "次の内容をSNS投稿文に: \(v)",
                                        apiKey: settings.apiKey)
                                } catch {
                                    ideaOut = "【SNS案】\(v) #日常 #高校生 #おすすめ"
                                }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    if !ideaOut.isEmpty {
                        Text(ideaOut).font(.footnote).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("作成")
        }
    }

    private func offlineContact() -> String {
        if templateID == "asobi" {
            return "\(to)、おつかれ！\n\(body_)なんだけど、よかったら一緒に行かない？\n無理なら全然大丈夫！"
        }
        if templateID == "kotowari" {
            return "\(to)、誘ってくれてありがとう！\n\(body_)の件、今回は行けなさそう。\nまた誘ってくれると嬉しいです！"
        }
        return "\(to)\nお疲れさまです、\(from)です。\n\(body_)。\nよろしくお願いします。\n（\(tone)）"
    }
}
