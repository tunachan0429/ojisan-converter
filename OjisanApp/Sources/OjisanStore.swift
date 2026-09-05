import Foundation
import Observation
import UIKit

// MARK: - 中央ストア（5タブ共有）
@Observable
@MainActor
final class OjisanStore {
    // 入力
    var input: String = "お疲れ様。明日の会議は10時からです。資料を送りますね。よろしくお願いします。"
    var options = OjisanOptions()

    // 結果
    var results: [OjisanResult] = []
    var lastReport: OjisanEngine.KimoReport?
    var lastConvertedText: String = ""
    var isConverting = false
    var convertMessage = ""
    var lastUsedGemini = false

    // 履歴・お気に入り・検索
    var history: [OjisanHistoryItem] = []
    var historyQuery: String = ""
    var showFavoritesOnly = false

    // 設定
    var apiKeyOverride: String = ""   // 空なら埋め込みキーを使う
    var geminiModel: String = OjisanConfig.defaultModel
    var appearance: OjisanAppearance = .system
    var totalCount: Int = 0

    // タブ
    var selectedTab = 0

    // トースト
    var toast: String = ""

    init() {
        let d = UserDefaults.standard
        options.target = d.string(forKey: "ojisan_target") ?? "ゆみちゃん"
        options.me = d.string(forKey: "ojisan_me") ?? "おじさん"
        if let tm = d.string(forKey: "ojisan_timemode"), let m = OjisanTimeMode(rawValue: tm) {
            options.timeMode = m
        }
        options.activePreset = d.string(forKey: "ojisan_preset") ?? "王道"
        options.kimo = d.integer(forKey: "ojisan_kimo") == 0 ? 4 : d.integer(forKey: "ojisan_kimo")
        options.emojiLevel = d.integer(forKey: "ojisan_emoji") == 0 ? 4 : d.integer(forKey: "ojisan_emoji")
        options.shitago = d.integer(forKey: "ojisan_shitago") == 0 ? 2 : d.integer(forKey: "ojisan_shitago")
        // toggles（初回true）
        if d.object(forKey: "ojisan_t_aisatsu") != nil {
            options.useAisatsu = d.bool(forKey: "ojisan_t_aisatsu")
            options.useHome = d.bool(forKey: "ojisan_t_home")
            options.useKinkyo = d.bool(forKey: "ojisan_t_kinkyo")
            options.useOffer = d.bool(forKey: "ojisan_t_offer")
            options.useKaomoji = d.bool(forKey: "ojisan_t_kaomoji")
            options.useKatakana = d.bool(forKey: "ojisan_t_katakana")
            options.useBikuri = d.bool(forKey: "ojisan_t_bikuri")
            options.useShime = d.bool(forKey: "ojisan_t_shime")
        }
        if let arr = d.stringArray(forKey: "ojisan_emoji_enabled"), !arr.isEmpty {
            options.emojiEnabled = arr
        }
        apiKeyOverride = d.string(forKey: "ojisan_gemini_key") ?? ""
        geminiModel = d.string(forKey: "ojisan_gemini_model") ?? OjisanConfig.defaultModel
        // 廃止モデルが保存されていたら現行既定へ移行（確実に動くため）
        if OjisanConfig.discontinuedModels.contains(geminiModel) || !OjisanConfig.geminiModels.contains(geminiModel) {
            geminiModel = OjisanConfig.defaultModel
        }
        if let ap = d.string(forKey: "ojisan_appearance"), let a = OjisanAppearance(rawValue: ap) {
            appearance = a
        }
        history = OjisanFileStore.load([OjisanHistoryItem].self, name: "ojisan-history.json", default: [])
        // 旧20件制限を撤廃（無制限化）。読み込み時に500件で足切りだけする
        if history.count > 500 { history = Array(history.prefix(500)) }
        totalCount = d.integer(forKey: "ojisan_total")
        // プリセット適用（スライダー整合）
        applyPreset(options.activePreset, silent: true)
    }

    // MARK: - 保存
    func saveSettings() {
        let d = UserDefaults.standard
        d.set(options.target, forKey: "ojisan_target")
        d.set(options.me, forKey: "ojisan_me")
        d.set(options.timeMode.rawValue, forKey: "ojisan_timemode")
        d.set(options.activePreset, forKey: "ojisan_preset")
        d.set(options.kimo, forKey: "ojisan_kimo")
        d.set(options.emojiLevel, forKey: "ojisan_emoji")
        d.set(options.shitago, forKey: "ojisan_shitago")
        d.set(options.useAisatsu, forKey: "ojisan_t_aisatsu")
        d.set(options.useHome, forKey: "ojisan_t_home")
        d.set(options.useKinkyo, forKey: "ojisan_t_kinkyo")
        d.set(options.useOffer, forKey: "ojisan_t_offer")
        d.set(options.useKaomoji, forKey: "ojisan_t_kaomoji")
        d.set(options.useKatakana, forKey: "ojisan_t_katakana")
        d.set(options.useBikuri, forKey: "ojisan_t_bikuri")
        d.set(options.useShime, forKey: "ojisan_t_shime")
        d.set(options.emojiEnabled, forKey: "ojisan_emoji_enabled")
        d.set(apiKeyOverride, forKey: "ojisan_gemini_key")
        d.set(geminiModel, forKey: "ojisan_gemini_model")
        d.set(appearance.rawValue, forKey: "ojisan_appearance")
        d.set(totalCount, forKey: "ojisan_total")
    }

    func saveHistory() {
        OjisanFileStore.save(history, name: "ojisan-history.json")
    }

    // MARK: - APIキー解決（埋め込み優先・設定で上書き可）
    var effectiveKey: String {
        let o = apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !o.isEmpty { return o }
        return OjisanConfig.embeddedGeminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var keyStatusText: String {
        if !apiKeyOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "設定キー使用中（\(effectiveKey.count)文字）"
        }
        if !OjisanConfig.embeddedGeminiKey.isEmpty {
            return "埋め込みキー使用中（\(effectiveKey.count)文字）"
        }
        return "キー未設定（ローカル変換のみ）"
    }

    // MARK: - プリセット
    func applyPreset(_ id: String, silent: Bool = false) {
        guard let p = OjisanData.presets.first(where: { $0.id == id }) else { return }
        options.activePreset = p.id
        options.kimo = p.kimo
        options.emojiLevel = p.emoji
        options.shitago = p.shitago
        if p.id == "昭和" {
            options.useKatakana = true
            options.useKaomoji = true
        }
        if p.id == "爽やか" {
            options.shitago = 1
        }
        saveSettings()
        if !silent { showToast("\(p.name) にしたよぉ〜😍💕") }
    }

    // MARK: - 変換
    func convert(useGemini: Bool = true) async {
        if isConverting { return }
        isConverting = true
        convertMessage = "変換中…"
        defer {
            isConverting = false
            convertMessage = ""
        }
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "こんにちは。元気にしてる？" : input
        let o = options

        // Gemini（キーあり・useGemini）→ 失敗したら黙ってローカルへ（HTML同等）
        if useGemini && !effectiveKey.isEmpty {
            do {
                let g = try await OjisanGemini.convert(raw: raw, options: o, firstModel: geminiModel, key: effectiveKey)
                let baseSeed = UInt32.random(in: 0...1_000_000)
                let a = OjisanEngine.localConvert(raw: raw, o: o, seed: baseSeed)
                let b = OjisanEngine.localConvert(raw: raw, o: o, seed: baseSeed &+ 7)
                results = [
                    OjisanResult(title: "🤖 Gemini仕上げ", badge: "AI高精度", isHot: true, text: g),
                    OjisanResult(title: "💪 ローカル案A", badge: "比較用", isHot: false, text: a),
                    OjisanResult(title: "💪 ローカル案B", badge: "比較用", isHot: false, text: b),
                ]
                lastUsedGemini = true
                afterConvert(raw: raw, main: g)
                showToast("仕上げたよぉ〜😍✨")
                return
            } catch {
                // フォールバック（エラー表示は結果タブに残さずトーストのみ短く）
                print("[ojisan gemini fallback]", error.localizedDescription)
            }
        }

        let s1 = UInt32.random(in: 0...1_000_000_000)
        let a = OjisanEngine.localConvert(raw: raw, o: o, seed: s1)
        let b = OjisanEngine.localConvert(raw: raw, o: o, seed: s1 &+ 101)
        let c = OjisanEngine.localConvert(raw: raw, o: o, seed: s1 &+ 202)
        results = [
            OjisanResult(title: "👑 本命", badge: "おすすめ", isHot: true, text: a),
            OjisanResult(title: "🎲 バリエーションB", badge: "別パターン", isHot: false, text: b),
            OjisanResult(title: "🎲 バリエーションC", badge: "別パターン", isHot: false, text: c),
        ]
        lastUsedGemini = false
        afterConvert(raw: raw, main: a)
    }

    private func afterConvert(raw: String, main: String) {
        lastConvertedText = main
        lastReport = OjisanEngine.kimoScore(text: main, o: options)
        totalCount += 1
        let item = OjisanHistoryItem(
            input: String(raw.prefix(200)),
            output: main,
            preset: options.activePreset,
            score: lastReport?.score ?? 0
        )
        history.insert(item, at: 0)
        if history.count > 500 { history = Array(history.prefix(500)) }
        saveHistory()
        saveSettings()
        // 結果タブへ自動遷移はしない（片手操作で選べるようトーストのみ）。初回のみ結果へ。
        if selectedTab == 0 && results.count == 3 && totalCount <= 1 {
            selectedTab = 1
        }
    }

    // MARK: - 履歴操作
    var filteredHistory: [OjisanHistoryItem] {
        var list = history
        if showFavoritesOnly { list = list.filter { $0.isFavorite } }
        let q = historyQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter { $0.input.localizedCaseInsensitiveContains(q) || $0.output.localizedCaseInsensitiveContains(q) }
        }
        return list
    }

    func toggleFavorite(_ id: UUID) {
        guard let i = history.firstIndex(where: { $0.id == id }) else { return }
        history[i].isFavorite.toggle()
        saveHistory()
    }

    func deleteHistory(_ id: UUID) {
        history.removeAll(where: { $0.id == id })
        saveHistory()
    }

    func clearHistory() {
        history = []
        saveHistory()
    }

    func restore(_ item: OjisanHistoryItem) {
        input = item.input
        if let p = OjisanData.presets.first(where: { $0.id == item.preset }) {
            applyPreset(p.id, silent: true)
        }
        lastConvertedText = item.output
        lastReport = OjisanEngine.kimoScore(text: item.output, o: options)
        results = [OjisanResult(title: "🕒 履歴から復元", badge: item.preset, isHot: true, text: item.output)]
        selectedTab = 0
        showToast("復元したよぉ〜😘💕")
    }

    // MARK: - トースト
    func showToast(_ msg: String) {
        toast = msg
    }

    // MARK: - テスト接続
    func testConnection() async -> String {
        do {
            let r = try await OjisanGemini.fetchOnce(
                model: geminiModel,
                key: effectiveKey,
                prompt: "「接続OK」とだけ返して。"
            )
            return "成功: \(String(r.prefix(80)))"
        } catch {
            return "失敗: \(OjisanGemini.friendly(error))"
        }
    }
}
