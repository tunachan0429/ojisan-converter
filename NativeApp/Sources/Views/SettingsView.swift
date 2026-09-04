import SwiftUI
import UniformTypeIdentifiers

// MARK: - 設定・データ管理
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chat
    @Environment(ReminderStore.self) private var reminders

    @State private var keyMsg = ""
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var showWipe = false

    var body: some View {
        NavigationStack {
            Form {
                Section("APIキー") {
                    SecureField("AIza…", text: Binding(
                        get: { settings.apiKey },
                        set: { settings.apiKey = $0.trimmingCharacters(in: .whitespaces) }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    Picker("ベースモデル", selection: Binding(
                        get: { settings.baseModel },
                        set: { settings.baseModel = $0 }
                    )) {
                        ForEach(AIConfig.baseModels, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("あなたの呼び方", text: Binding(
                        get: { settings.myCall },
                        set: { settings.myCall = $0 }
                    ))
                    HStack {
                        Button("接続テスト") {
                            Task {
                                keyMsg = "テスト中…"
                                do {
                                    let r = try await settings.testConnection()
                                    keyMsg = "成功: \(r)"
                                } catch {
                                    keyMsg = "失敗: \(String(describing: error).prefix(200))"
                                }
                            }
                        }
                        Button("削除", role: .destructive) {
                            settings.apiKey = ""
                            keyMsg = ""
                        }
                    }
                    if !keyMsg.isEmpty {
                        Text(keyMsg).font(.footnote).foregroundStyle(.secondary)
                    }
                    Link("キーの取得はこちら（無料）",
                         destination: URL(string: "https://aistudio.google.com/app/apikey")!)
                        .font(.footnote)
                }
                Section("用途別の割当") {
                    ForEach(routerRows(), id: \.self) { Text($0).font(.footnote) }
                }
                Section("データ管理") {
                    Button("バックアップ書き出し") { prepareExport() }
                    Button("バックアップ読み込み") { showImporter = true }
                    Button("全部消す", role: .destructive) { showWipe = true }
                    Text("チャット・リマインダーはこのiPhone内に保存。画像は保存しません。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("このアプリについて") {
                    Text("SwiftUIネイティブ版。GitHub ActionsのMacでビルドした署名なしIPAをSideloadly / AltStoreで入れます。無料Apple IDは7日で期限切れ→入れ直し。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .confirmationDialog("全部消しますか？", isPresented: $showWipe, titleVisibility: .visible) {
                Button("消す", role: .destructive) { wipe() }
                Button("やめる", role: .cancel) {}
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { importBackup(url) }
            }
            .sheet(isPresented: $showExporter) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
        }
    }

    private func routerRows() -> [String] {
        [
            "通常・速い：flash-lite・低温度",
            "通常・高精度：flash・中温度",
            "調べる／自動：flash＋google_search・温度1.0・出典抽出",
            "画像認識：flash Vision固定・低温度",
            "連絡・生成・ToDo・要約：lite固定で枠節約",
            "音声入力：端末の音声認識（無料・キー不要）",
            "天気・Wikipedia：非AIの無料API直叩き"
        ]
    }

    private func prepareExport() {
        let backup = Backup(threads: chat.threads, reminders: reminders.items, exported: Date())
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(backup)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("assistant-backup.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
            showExporter = true
        } catch {
            keyMsg = "書き出しに失敗しました"
        }
    }

    private func importBackup(_ url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let backup = try decoder.decode(Backup.self, from: data)
            chat.threads = backup.threads
            if let first = backup.threads.first { chat.currentID = first.id }
            chat.save()
            reminders.items = backup.reminders
            reminders.save()
            keyMsg = "読み込みました"
        } catch {
            keyMsg = "読み込みに失敗しました"
        }
    }

    private func wipe() {
        chat.threads = [ChatThread(mode: "all", title: "はじめて")]
        chat.currentID = chat.threads.first?.id
        chat.save()
        reminders.items = []
        reminders.save()
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
