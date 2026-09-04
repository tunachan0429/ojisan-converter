import Foundation

// MARK: - 用途別AIルーター（Web版と同一仕様）
enum EngineKey: String {
    case chatFast = "chat_fast"
    case chatHigh = "chat_high"
    case search
    case vision
    case light
}

struct EngineSpec: Sendable {
    let label: String
    let model: String
    let temperature: Double
    let maxTokens: Int
}

enum SearchMode: String, Codable, CaseIterable {
    case off, auto, on
    var label: String {
        switch self {
        case .off: return "しない"
        case .auto: return "自動"
        case .on: return "する"
        }
    }
}

enum Speed: String, Codable {
    case fast, high
}

struct AIConfig {
    static let engines: [EngineKey: EngineSpec] = [
        .chatFast: EngineSpec(label: "速い", model: "gemini-2.0-flash-lite", temperature: 0.7, maxTokens: 1000),
        .chatHigh: EngineSpec(label: "高精度", model: "gemini-2.0-flash", temperature: 0.8, maxTokens: 1400),
        .search: EngineSpec(label: "検索連携", model: "gemini-2.0-flash", temperature: 1.0, maxTokens: 1400),
        .vision: EngineSpec(label: "画像認識", model: "gemini-2.0-flash", temperature: 0.4, maxTokens: 1200),
        .light: EngineSpec(label: "軽量", model: "gemini-2.0-flash-lite", temperature: 0.6, maxTokens: 600)
    ]

    static func pickEngine(hasImage: Bool, search: SearchMode, speed: Speed) -> EngineKey {
        if hasImage { return .vision }
        if search != .off { return .search }
        return speed == .fast ? .chatFast : .chatHigh
    }

    static let baseModels = [
        "gemini-2.0-flash-lite",
        "gemini-2.0-flash",
        "gemini-1.5-flash"
    ]
}

// MARK: - 会話モード
struct ChatMode: Identifiable {
    let id: String
    let name: String
    let detail: String
    let system: String
}

struct Modes {
    static let all: [ChatMode] = [
        ChatMode(id: "all", name: "なんでも", detail: "日常の助手",
                 system: "あなたは高校生の頼れる日常アシスタント。親しみやすく、簡潔で実用的に答える。箇条書きを多用。"),
        ChatMode(id: "ask", name: "質問", detail: "解説・調査",
                 system: "あなたは分かりやすい解説者。結論→理由→具体例の順。最後に「次にやる1歩」を付ける。検索結果がある場合は出典を意識した断定にする。"),
        ChatMode(id: "nayami", name: "悩み", detail: "傾聴・整理",
                 system: "あなたは共感的な相談相手。まず共感し、悩みを3点に整理し、選択肢と小さな一歩を提案。断定的な医療・法律判断はせず、必要なら専門家相談を促す。"),
        ChatMode(id: "idea", name: "生成", detail: "アイデア出し",
                 system: "あなたは発想豊かな企画マン。高校生向けにノリ良く、実現可能性も一言付ける。"),
        ChatMode(id: "renraku", name: "連絡", detail: "文面作成",
                 system: "あなたは連絡文のプロ。相手・用件から丁寧で失礼のない文面を作る。LINE用短文と丁寧文の2案を出す。"),
        ChatMode(id: "yoyaku", name: "要約", detail: "短く整える",
                 system: "あなたは編集者。長い文章を3行要約→箇条書き→短文の順で整える。誤字脱字も直す。")
    ]

    static func by(id: String) -> ChatMode {
        all.first(where: { $0.id == id }) ?? all[0]
    }
}

// MARK: - フォローアップ候補（追加通信なし）
struct FollowUps {
    static func make(mode: String, userText: String) -> [String] {
        let kw = String(userText.replacingOccurrences(of: "\n", with: " ").prefix(14))
        let key = kw.isEmpty ? "これ" : kw
        switch mode {
        case "ask":
            return ["「\(key)」の具体例をもっと", "反対意見・注意点も教えて", "次にやる1歩だけ教えて"]
        case "nayami":
            return ["選択肢を3つに絞って", "明日の一歩だけ決めて", "同じ悩みの乗り越え方を教えて"]
        case "idea":
            return ["10案に広げて", "1案だけ深掘りして", "低予算版も出して"]
        case "renraku":
            return ["短いLINE版にして", "丁寧版にして", "件名も付けて"]
        case "yoyaku":
            return ["3行でまとめ直して", "箇条書きだけにして", "小学生向けに言い換えて"]
        default:
            return ["深掘りして", "3行でまとめ直して", "別の視点でも教えて"]
        }
    }
}

// MARK: - オフライン簡易回答（Web版と同一文面）
struct LocalFallback {
    static func make(mode: String, text: String, hasImage: Bool) -> String {
        if hasImage {
            return "画像を受け付けたけど、オフライン＋キーなしでは解析できません。「設定」でキーを入れてネット接続で送り直してください。"
        }
        switch mode {
        case "renraku":
            return "【下書き（オフライン）】\n\(text)\n\n→ APIキー設定で丁寧文2案に自動仕上げできます。"
        case "yoyaku":
            return "【3行要約（オフライン）】\n・ \(String(text.prefix(120)))\n・ 要点を確認してください"
        case "idea":
            return "【10案（オフライン雛形）】\n1. 定番 2. 限定 3. コラボ 4. ランキング 5. 体験型 6. SNS連動 7. 夜企画 8. 初心者枠 9. ガチ枠 10. ネタ枠\n\nテーマ「\(String(text.prefix(40)))」"
        case "nayami":
            return "つらいね、よく話してくれたね。\n整理すると：\n1. 何が起きたか\n2. 一番しんどい点\n3. 明日できる小さい一歩\n\n「\(String(text.prefix(60)))」について詳しく教えてね。※深刻な場合は信頼できる大人にも相談してね。"
        default:
            return "【簡易回答（オフライン）】\n「\(String(text.prefix(80)))」を受け付けたよ。ネット＋キーで高精度回答になります。"
        }
    }
}

// MARK: - 連絡テンプレ / 都市
struct ContactTemplate: Identifiable {
    let id: String
    let name: String
    let hint: String
}

struct Presets {
    static let contactTemplates: [ContactTemplate] = [
        ContactTemplate(id: "bukatu", name: "部活欠席", hint: "部活を休みます。"),
        ContactTemplate(id: "baito", name: "バイト応募", hint: "応募・面接希望。"),
        ContactTemplate(id: "asobi", name: "遊びの誘い", hint: "友達を誘う。"),
        ContactTemplate(id: "kotowari", name: "断り", hint: "角が立たない断り。"),
        ContactTemplate(id: "orei", name: "お礼", hint: "お礼。"),
        ContactTemplate(id: "ayamaru", name: "謝罪", hint: "謝罪。")
    ]

    static let cities: [(name: String, lat: Double, lon: Double)] = [
        ("東京", 35.68, 139.69),
        ("大阪", 34.69, 135.50),
        ("名古屋", 35.18, 136.90),
        ("札幌", 43.06, 141.35),
        ("仙台", 38.26, 140.87),
        ("広島", 34.38, 132.46),
        ("福岡", 33.59, 130.40),
        ("那覇", 26.21, 127.68)
    ]
}
