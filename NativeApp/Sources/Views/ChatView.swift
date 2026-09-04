import PhotosUI
import SwiftUI

// MARK: - チャット（優先画面・Web版と同一仕様）
struct ChatView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chat

    @State private var input = ""
    @State private var attached: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPickerShown = false
    @State private var modelSheetShown = false
    @State private var drawerShown = false
    @StateObject private var voice = VoiceTranscriber()
    @State private var voiceBase = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                modeRow
                messages
                composer
            }
            if drawerShown {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { drawerShown = false }
                drawer
            }
        }
        .sheet(isPresented: $modelSheetShown) { modelSheet }
        .photosPicker(isPresented: $photoPickerShown, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in loadPhoto(item) }
    }

    // MARK: 上部バー（☰・モデルピル・＋）
    private var topBar: some View {
        HStack {
            Button { drawerShown = true } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3).frame(width: 40, height: 40)
            }
            Spacer()
            Button { modelSheetShown = true } label: {
                HStack(spacing: 6) {
                    Text(settings.pillText).font(.headline)
                    Circle()
                        .fill(settings.hasKey ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.quaternary, in: Capsule())
            }
            Spacer()
            Button { chat.newThread() } label: {
                Image(systemName: "plus")
                    .font(.title3).frame(width: 40, height: 40)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: モード切替
    private var modeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Modes.all) { m in
                    Button {
                        chat.setMode(m.id)
                    } label: {
                        VStack(spacing: 1) {
                            Text(m.name).font(.subheadline).fontWeight(.semibold)
                            Text(m.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(chat.activeMode == m.id ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            if chat.activeMode == m.id {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    // MARK: 会話
    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let i = chat.currentIndex, chat.threads[i].messages.isEmpty {
                        hero
                    } else if let i = chat.currentIndex {
                        ForEach(chat.threads[i].messages) { m in
                            messageRow(m)
                                .id(m.id)
                        }
                    }
                    if chat.sending { TypingDots() }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .animation(.spring(response: 0.3), value: chat.threads.map(\.messages.count).reduce(0, +))
            }
            .onChange(of: chat.threads.map(\.messages.count).reduce(0, +)) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: chat.currentID) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    private func messageRow(_ m: ChatMessage) -> some View {
        Group {
            if m.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    Text(m.text)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if !m.engine.isEmpty {
                        Text(m.engine).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(m.text).textSelection(.enabled)
                    if !m.sources.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(m.sources.prefix(5)) { s in
                                if let url = URL(string: s.uri) {
                                    Link("出典: \(String(s.title.prefix(24)))", destination: url)
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                    if !m.follow.isEmpty, !m.isError {
                        FlowChips(items: m.follow) { f in
                            Task { await chat.send(text: f) }
                        }
                    }
                    if m.isError {
                        Button("再試行する") {
                            Task { await chat.retry(messageID: m.id) }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Text(m.time, format: .dateTime.month().day().hour().minute())
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 空状態（Gemini式ヒーロー）
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    RadialGradient(colors: [.blue.opacity(0.35), .purple.opacity(0.3)],
                                   center: .topLeading, startRadius: 10, endRadius: 220)
                )
                .overlay {
                    RadialGradient(colors: [.green.opacity(0.25), .clear],
                                   center: .bottomTrailing, startRadius: 10, endRadius: 200)
                }
                .frame(height: 118)
                .padding(.bottom, 14)
            Text(dateGreeting()).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
            (Text("何を") + Text("お手伝い").foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)) + Text("しますか？"))
                .font(.system(size: 29, weight: .bold))
                .padding(.bottom, 4)
            Text("質問・調べもの・文章作成・写真の読み取りができます。")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.bottom, 14)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                SuggestionCard(icon: "newspaper", tint: .blue, title: "最新ニュース",
                               action: { Task { await chat.send(text: "今日の最新ニュースを要約して") } })
                SuggestionCard(icon: "envelope", tint: .green, title: "連絡文を作る",
                               action: { Task { await chat.send(text: "丁寧な連絡文の例を作って") } })
                SuggestionCard(icon: "lightbulb", tint: .orange, title: "アイデアを出す",
                               action: { Task { await chat.send(text: "文化祭の出し物アイデアを10個出して") } })
                SuggestionCard(icon: "camera", tint: .purple, title: "写真を読み取る",
                               action: { photoPickerShown = true })
            }
            quickChips.padding(.top, 10)
        }
    }

    private func dateGreeting() -> String {
        let d = Date(), cal = Calendar.current
        let wd = ["日", "月", "火", "水", "木", "金", "土"][cal.component(.weekday, from: d) - 1]
        let h = cal.component(.hour, from: d)
        let g = h < 5 ? "お疲れさまです" : h < 10 ? "おはようございます" : h < 17 ? "こんにちは" : "こんばんは"
        return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日（\(wd)）・\(g)"
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["3行で要約して：", "丁寧な文章に直して：", "短く分かりやすくして：", "3パターン案を出して：", "メリット・デメリットで整理して："], id: \.self) { q in
                    Button(String(q.dropLast())) { input = q + input }
                        .font(.footnote)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: 入力欄
    private var composer: some View {
        VStack(spacing: 2) {
            if let img = attached {
                HStack {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    Text("画像1枚添付中（送信時のみ使用・保存しません）")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("外す") { attached = nil }.font(.footnote)
                }
                .padding(.horizontal, 12)
            }
            HStack(alignment: .bottom, spacing: 2) {
                Button { photoPickerShown = true } label: {
                    Image(systemName: "plus").font(.title3).frame(width: 38, height: 38)
                }
                Button {
                    Task {
                        if voice.isRecording {
                            await voice.toggle { _ in }
                        } else {
                            voiceBase = input
                            await voice.toggle { t in input = voiceBase + t }
                        }
                    }
                } label: {
                    Image(systemName: voice.isRecording ? "stop.circle.fill" : "mic")
                        .font(.title3).foregroundStyle(voice.isRecording ? .red : .primary)
                        .frame(width: 38, height: 38)
                }
                TextField("メッセージを入力", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.vertical, 8)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .frame(width: 36, height: 36)
                        .background(canSend ? Color.primary : Color(.systemGray4), in: Circle())
                        .foregroundStyle(canSend ? Color(.systemBackground) : Color(.systemGray))
                }
                .disabled(!canSend || chat.sending)
            }
            .padding(.horizontal, 6).padding(.vertical, 6)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.1), radius: 8, y: 1)
            if let err = voice.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            Text("回答は必ず確認してください。").font(.caption2).foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attached != nil
    }

    private func send(preset: String? = nil) {
        let text = preset ?? input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attached != nil else { return }
        let img = attached
        input = ""
        attached = nil
        Task {
            var payload: [GeminiImage] = []
            if let img, let data = downscaledJPEG(img) {
                payload = [GeminiImage(mime: "image/jpeg", base64: data.base64EncodedString())]
            }
            await chat.send(text: text, images: payload)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                attached = ui
            }
            photoItem = nil
        }
    }

    // MARK: モデルパネル
    private var modelSheet: some View {
        NavigationStack {
            Form {
                Section("検索") {
                    Picker("検索", selection: Binding(
                        get: { settings.searchMode },
                        set: { settings.searchMode = $0 }
                    )) {
                        ForEach(SearchMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(engineMemo()).font(.footnote).foregroundStyle(.secondary)
                }
                Section("応答") {
                    Picker("応答", selection: Binding(
                        get: { settings.speed },
                        set: { settings.speed = $0 }
                    )) {
                        Text("速い").tag(Speed.fast)
                        Text("高精度").tag(Speed.high)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("モデルと検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { modelSheetShown = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func engineMemo() -> String {
        let e = AIConfig.pickEngine(hasImage: attached != nil,
                                    search: settings.searchMode,
                                    speed: settings.speed)
        let spec = AIConfig.engines[e]!
        var s = "使用AI: \(spec.label) (\(spec.model))"
        s += settings.searchMode == .off ? "・検索OFF" : "・検索\(settings.searchMode == .on ? "ON" : "自動")"
        if attached != nil { s += "・画像あり→Vision固定" }
        return s
    }

    // MARK: 履歴ドロワー
    private var drawer: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("履歴").font(.headline)
                    Spacer()
                    Button { drawerShown = false } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
                Button("新規チャット") {
                    chat.newThread()
                    drawerShown = false
                }
                .buttonStyle(.bordered)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(chat.threads) { t in
                            Button {
                                chat.select(t.id)
                                drawerShown = false
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.title.isEmpty ? "無題" : t.title)
                                        .font(.body).lineLimit(1)
                                    Text("\(t.messages.count)件のメッセージ")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(t.id == chat.currentID ? Color(.secondarySystemBackground) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("削除", role: .destructive) { chat.deleteThread(t.id) }
                            }
                        }
                    }
                }
                Button("現在のチャットを消去", role: .destructive) { chat.clearCurrent() }
                    .font(.body)
            }
            .padding()
            .frame(width: min(UIScreen.main.bounds.width * 0.84, 320))
            .frame(maxHeight: .infinity)
            .background(Color(.systemBackground))
            .transition(.move(edge: .leading))
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 部品
struct TypingDots: View {
    @State private var on = false
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle().fill(Color.secondary).frame(width: 7, height: 7)
                    .offset(y: on ? -3 : 0)
                    .opacity(on ? 1 : 0.3)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                               value: on)
            }
        }
        .padding(.vertical, 8)
        .onAppear { on = true }
    }
}

struct FlowChips: View {
    let items: [String]
    let action: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items.prefix(3), id: \.self) { f in
                Button(f) { action(f) }
                    .font(.footnote)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .buttonStyle(.plain)
            }
        }
    }
}

struct SuggestionCard: View {
    let icon: String
    let tint: Color
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(tint)
                Text(title).font(.subheadline).fontWeight(.medium)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18).stroke(Color(.separator), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

// 簡易フロー配置
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var h: CGFloat = 0
        var w: CGFloat = 0
        for row in rows {
            h += row.h
            w = max(w, row.w)
        }
        if !rows.isEmpty { h += spacing * CGFloat(rows.count - 1) }
        return CGSize(width: w, height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for idx in row.items {
                subviews[idx].place(at: CGPoint(x: x, y: y),
                                    proposal: ProposedViewSize(width: row.widths[idx], height: row.h))
                x += (row.widths[idx] ?? 0) + spacing
            }
            y += row.h + spacing
        }
    }
    private struct Row {
        var items: [Int] = []
        var widths: [Int: CGFloat] = [:]
        var w: CGFloat = 0
        var h: CGFloat = 0
    }
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxW = proposal.width ?? .infinity
        var rows: [Row] = []
        var cur = Row()
        for (i, sv) in subviews.enumerated() {
            let size = sv.sizeThatFits(.unspecified)
            if !cur.items.isEmpty, cur.w + spacing + size.width > maxW {
                rows.append(cur)
                cur = Row()
            }
            cur.items.append(i)
            cur.widths[i] = size.width
            cur.w += (cur.items.count > 1 ? spacing : 0) + size.width
            cur.h = max(cur.h, size.height)
        }
        if !cur.items.isEmpty { rows.append(cur) }
        return rows
    }
}

func downscaledJPEG(_ image: UIImage, maxEdge: CGFloat = 1280) -> Data? {
    let scale = min(1, maxEdge / max(image.size.width, image.size.height))
    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: size)
    let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return resized.jpegData(compressionQuality: 0.85)
}
