import Foundation
import Observation
import UserNotifications

// MARK: - 設定
@Observable
@MainActor
final class SettingsStore {
    var apiKey: String = "" { didSet { save() } }
    var baseModel: String = AIConfig.baseModels[0] { didSet { save() } }
    var myCall: String = "" { didSet { save() } }
    var searchMode: SearchMode = .auto { didSet { save() } }
    var speed: Speed = .high { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        apiKey = d.string(forKey: "bannou_gemini_key") ?? ""
        baseModel = d.string(forKey: "bannou_gemini_model") ?? AIConfig.baseModels[0]
        myCall = d.string(forKey: "bannou_mycal") ?? ""
        if let s = d.string(forKey: "bannou_search"), let m = SearchMode(rawValue: s) { searchMode = m }
        if let s = d.string(forKey: "bannou_speed"), let v = Speed(rawValue: s) { speed = v }
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(apiKey, forKey: "bannou_gemini_key")
        d.set(baseModel, forKey: "bannou_gemini_model")
        d.set(myCall, forKey: "bannou_mycal")
        d.set(searchMode.rawValue, forKey: "bannou_search")
        d.set(speed.rawValue, forKey: "bannou_speed")
    }

    var hasKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }

    var pillText: String {
        let base = speed == .fast ? "速い" : "高精度"
        switch searchMode {
        case .off: return base
        case .auto: return base + "・検索自動"
        case .on: return base + "・検索ON"
        }
    }

    func testConnection() async throws -> String {
        let r = try await GeminiClient.generate(
            system: "あなたはテスト用アシスタント。「接続OK」とだけ返して。",
            userText: "接続テスト",
            engine: .light, search: .off, apiKey: apiKey)
        return String(r.text.prefix(80))
    }
}

// MARK: - チャット
@Observable
@MainActor
final class ChatStore {
    var threads: [ChatThread] = []
    var currentID: UUID?
    var activeMode = "all"
    var sending = false

    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        self.threads = FileStore.load([ChatThread].self, name: "threads.json", default: [])
        if threads.isEmpty {
            threads = [ChatThread(mode: "all", title: "はじめて", messages: [
                ChatMessage(role: .ai,
                            text: "こんにちは。調べものは「調べる」、相談や作成は「調べない」がおすすめです。画像ボタンから写真も送れます。",
                            time: Date(), engine: "高精度")
            ])]
        }
        currentID = threads.first?.id
    }

    var currentIndex: Int? {
        threads.firstIndex(where: { $0.id == currentID })
    }

    func save() {
        FileStore.save(threads, name: "threads.json")
    }

    func select(_ id: UUID) {
        currentID = id
        if let i = currentIndex { activeMode = threads[i].mode }
    }

    func setMode(_ id: String) {
        activeMode = id
        if let i = currentIndex {
            threads[i].mode = id
            save()
        }
    }

    func newThread() {
        let t = ChatThread(mode: activeMode, title: "相談\(threads.count + 1)")
        threads.insert(t, at: 0)
        currentID = t.id
        save()
    }

    func deleteThread(_ id: UUID) {
        threads.removeAll(where: { $0.id == id })
        if threads.isEmpty {
            threads = [ChatThread(mode: activeMode, title: "はじめて")]
        }
        if currentID == id { currentID = threads.first?.id }
        save()
    }

    func clearCurrent() {
        guard let i = currentIndex else { return }
        threads[i].messages = []
        threads[i].summary = ""
        threads[i].summaryCount = 0
        save()
    }

    func send(text: String, images: [GeminiImage] = []) async {
        await sendInner(text: text, images: images)
    }

    func retry(messageID: UUID) async {
        guard let i = currentIndex,
              let aiIdx = threads[i].messages.firstIndex(where: { $0.id == messageID }),
              threads[i].messages[aiIdx].isError else { return }
        let pending = threads[i].messages[aiIdx].pendingText ?? ""
        threads[i].messages.remove(at: aiIdx)
        save()
        await sendInner(text: pending, images: [])
    }

    private func sendInner(text: String, images: [GeminiImage]) async {
        guard !sending, let i = currentIndex else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || !images.isEmpty else { return }
        sending = true
        defer { sending = false }

        let hasImage = !images.isEmpty
        let engine = AIConfig.pickEngine(hasImage: hasImage,
                                         search: settings.searchMode,
                                         speed: settings.speed)
        let userLabel = (body.isEmpty ? "この画像を解説して" : body) + (hasImage ? "\n[画像1枚付き]" : "")
        threads[i].mode = activeMode
        threads[i].messages.append(ChatMessage(role: .user, text: userLabel, time: Date()))
        if threads[i].title.isEmpty || threads[i].title.hasPrefix("相談") || threads[i].title == "はじめて" {
            threads[i].title = String((body.isEmpty ? "画像相談" : body).prefix(14))
        }
        let threadID = threads[i].id
        save()

        let mode = Modes.by(id: activeMode)
        var sys = mode.system
        if hasImage {
            sys = "あなたは画像理解の専門家。写真・スクショ・図表・手書きを日本語で正確に読む。文字は原文引用→要約→気づきの順。断定できない所は推測と明記。" + sys
        }
        if settings.searchMode == .on {
            sys += " 必ず最新情報を検索して、古い知識だけで答えない。"
        }
        let hist = threads[i].messages.dropLast().suffix(8).map {
            HistoryItem(role: $0.role, text: $0.text)
        }
        do {
            let r = try await GeminiClient.generate(
                system: sys,
                userText: body.isEmpty ? "この画像を詳しく解説してください。" : body,
                history: Array(hist),
                images: images,
                engine: engine,
                search: settings.searchMode,
                summary: threads[i].summary,
                callerName: settings.myCall,
                apiKey: settings.apiKey)
            guard let j = threads.firstIndex(where: { $0.id == threadID }) else { return }
            let label = r.engineLabel + ((r.grounded && settings.searchMode != .off) ? "・検索" : "")
            threads[j].messages.append(ChatMessage(
                role: .ai, text: r.text, time: Date(),
                sources: r.sources,
                follow: FollowUps.make(mode: activeMode, userText: body.isEmpty ? "画像の内容" : body),
                engine: label))
            save()
            Task { await self.refreshSummaryIfNeeded(threadID: threadID) }
        } catch {
            guard let j = threads.firstIndex(where: { $0.id == threadID }) else { return }
            let msg = (error as? GeminiError)?.errorDescription ?? error.localizedDescription
            var fb = LocalFallback.make(mode: activeMode, text: body, hasImage: hasImage)
            if msg != "NO_KEY" { fb += "\n\n(エラー: \(String(msg.prefix(80))))" }
            threads[j].messages.append(ChatMessage(
                role: .ai, text: fb, time: Date(),
                engine: "オフライン", isError: true, pendingText: body))
            save()
        }
    }

    private func refreshSummaryIfNeeded(threadID: UUID) async {
        guard let j = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let t = threads[j]
        guard t.messages.count >= 8, t.messages.count - t.summaryCount >= 6 else { return }
        let log = t.messages.suffix(10).map { m in
            "\(m.role == .user ? "Q: " : "A: ")\(String(m.text.prefix(200)))"
        }.joined(separator: "\n")
        do {
            let s = try await GeminiClient.generateLight(
                system: "あなたは要約係。会話を200字以内で要点のみ要約。",
                userText: "以下を要約:\n\(log)",
                apiKey: settings.apiKey)
            guard let k = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[k].summary = String(s.prefix(400))
            threads[k].summaryCount = threads[k].messages.count
            save()
        } catch {
            // 要約失敗は無視（次回に再試行）
        }
    }
}

// MARK: - リマインダー（本物のローカル通知付き）
@Observable
@MainActor
final class ReminderStore {
    var items: [ReminderItem] = []

    init() {
        items = FileStore.load([ReminderItem].self, name: "reminders.json", default: [])
    }

    func save() {
        FileStore.save(items, name: "reminders.json")
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func add(title: String, when: Date, repeatMode: RepeatMode, memo: String) {
        var item = ReminderItem(title: title, when: when, repeatMode: repeatMode, memo: memo)
        item.notifID = schedule(item)
        items.append(item)
        save()
    }

    func toggleDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].done.toggle()
        if items[i].done {
            cancel(items[i])
        } else {
            items[i].notifID = schedule(items[i])
        }
        save()
    }

    func remove(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        cancel(items[i])
        items.remove(at: i)
        save()
    }

    private func cancel(_ item: ReminderItem) {
        if let nid = item.notifID {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [nid])
        }
    }

    @discardableResult
    private func schedule(_ item: ReminderItem) -> String? {
        guard item.when > Date() else { return nil }
        let nid = UUID().uuidString
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.memo.isEmpty ? "時間だよ" : item.memo
        content.sound = .default
        let cal = Calendar.current
        let comps: DateComponents
        switch item.repeatMode {
        case .none:
            comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: item.when)
        case .daily:
            comps = cal.dateComponents([.hour, .minute], from: item.when)
        case .weekly:
            comps = cal.dateComponents([.weekday, .hour, .minute], from: item.when)
        }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps,
                                                    repeats: item.repeatMode != .none)
        let req = UNNotificationRequest(identifier: nid, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
        return nid
    }
}
