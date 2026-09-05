import Foundation

// MARK: - 埋め込み設定（APIキーはここ1箇所だけ）
// ユーザーから受け取ったキーをここに貼る。空なら設定タブ入力＋ローカル変換で動作。
// 注意: IPAに埋め込むと抜き出し可能なので、公開リポジトリでは空推奨・個人利用前提。
enum OjisanConfig {
    // ビルド時にGitHub ActionsのSecret（OJISAN_GEMINI_KEY）から自動注入される。
    // 手元ビルド用に直接貼る場合は下の "" に入れても動くが、push前に必ず空に戻すこと。
    static let embeddedGeminiKey: String = ""

    static let appName = "オジサン翻訳機"
    static let bundleID = "com.my.bannou.ojisan"

    // 動作確認済みモデル体系（2026-09: 旧2.x/1.5は新規ユーザー向けに提供終了のため3.x系へ移行）
    static let geminiModels = [
        "gemini-3.6-flash",
        "gemini-flash-latest",
        "gemini-3.5-flash",
        "gemini-3.5-flash-lite",
        "gemini-flash-lite-latest"
    ]
    static let defaultModel = "gemini-3.6-flash"

    // 廃止済み（保存値の移行用。ヒットしたらdefaultModelに置換する）
    static let discontinuedModels: Set<String> = [
        "gemini-2.5-flash", "gemini-2.0-flash", "gemini-2.0-flash-lite",
        "gemini-1.5-flash", "gemini-2.5-flash-lite"
    ]

    static let keyDocURL = "https://aistudio.google.com/app/apikey"
}

// MARK: - プリセット
struct OjisanPreset: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var desc: String
    var kimo: Int
    var emoji: Int
    var shitago: Int
}

enum OjisanData {
    static let presets: [OjisanPreset] = [
        OjisanPreset(id: "王道", name: "👑 王道おじさん", desc: "THE おじさん構文", kimo: 4, emoji: 4, shitago: 2),
        OjisanPreset(id: "爽やか", name: "☀️ 爽やかおじさん", desc: "朝から元気いっぱい", kimo: 2, emoji: 3, shitago: 1),
        OjisanPreset(id: "上司", name: "💼 セクハラ上司", desc: "飲み会の誘いがち", kimo: 5, emoji: 3, shitago: 4),
        OjisanPreset(id: "パパ活", name: "💰 パパ活おじさん", desc: "おごりたがり", kimo: 4, emoji: 5, shitago: 5),
        OjisanPreset(id: "昭和", name: "📻 昭和おじさん", desc: "顔文字・カタカナ多め", kimo: 3, emoji: 2, shitago: 1),
        OjisanPreset(id: "メンヘラ", name: "🥺 泣き落としおじさん", desc: "返信まだかなぁ…", kimo: 5, emoji: 4, shitago: 3),
    ]

    static let emojiAll: [String] = [
        "❤️","💕","😍","😘","✨","🌸","☀️","🎵","😅","💦","🙏","💌",
        "‼️","❗","😎","👍","🍺","🍖","⛳","🌃","💪","😊","💖","🥺",
        "🎶","🍣","☕","🌹","💗","😉","🤣","🫶"
    ]

    static let samples: [String] = [
        "お疲れ様。明日の会議は10時からです。資料を送りますね。",
        "今日はありがとう。楽しかったです。またご飯行きましょう。",
        "おはよう。体調は大丈夫？無理しないでね。",
        "この前の写真見たよ。とても綺麗だった。",
        "了解しました。確認しておきます。",
        "久しぶりだね。元気にしてた？",
        "誕生日おめでとう。素敵な一年にしてね。",
        "ごめんね。返信遅くなった。許してね。",
        "今日のプレゼン良かったよ。お疲れ様でした。",
        "週末は空いてる？美味しい店見つけたんだ。"
    ]

    static let greetMorning = ["おはよう☀️","ヤッホー😍おはよう☀️","おっはよ〜☀️✨"]
    static let greetNoon = ["やぁ😊こんにちは☀️","ヤッホー😍","お疲れ様〜🍺✨"]
    static let greetNight = ["こんばんは🌃✨","やぁ🌃今日も一日お疲れ様〜🍺😊","こんばんは😘⭐"]

    static let weather = [
        "今日もいい天気だねぇ〜☀️✨",
        "今日は暑いねぇ〜💦水分とってねぇ〜🙏💕",
        "寒くなってきたけど体調大丈夫〜❓😟💕",
        "桜が綺麗だねぇ〜🌸{t}と見に行きたいなぁ😍💕",
        "雨だけど足元気をつけてねぇ〜☔💦"
    ]

    static let compliments = [
        "今日も{t}は可愛いねぇ〜😍💕",
        "{t}の笑顔を思い出すだけで{me}は元気が出ちゃうよぉ〜💪😍",
        "{t}ってホント気が利くよねぇ〜✨尊敬しちゃうなぁ🙏💕",
        "写真見たけどホント綺麗だったよぉ〜🌸ドキドキしちゃった😍💓",
        "{t}は相変わらずモテるでしょぉ〜😉⁉️{me}は心配だよぉ〜💦💕"
    ]

    static let kinkyo = [
        "{me}は今日ゴルフだったよぉ〜⛳😅スコアはイマイチだったけど楽しかったなぁ🎵",
        "{me}はさっきまで飲んでたよぉ〜🍺😎美味しいお刺身食べたよぉ〜🍣✨",
        "今日は仕事でヘトヘトだよぉ〜💦でも{t}のこと考えたら頑張れちゃう😍💪",
        "さっき愛犬の散歩してたよぉ〜🐶🎵{t}もワンちゃん好きだったよねぇ〜😊💕",
        "健康診断で医者に痩せろって言われちゃったよぉ〜(^_^;)💦なんちゃって🤣"
    ]

    static let offer1 = ["落ち着いたらお茶でもどうかなぁ〜☕😊無理しないでねぇ〜💕"]
    static let offer2 = ["今度美味しいお肉食べに行こうよぉ〜🍖😍{me}がおごっちゃうよぉ〜💕"]
    static let offer3 = ["今度二人でゆっくり飲もうよぉ〜🍺😘いい店知ってるんだぁ〜✨"]
    static let offer4 = ["週末空いてる〜❓😍ドライブでも行こうよぉ〜🚗💕二人きりで…なんちゃって😉💦"]
    static let offer5 = ["会いたいなぁ〜🥺💕いつ会えるかなぁ〜❓😘ホテル…じゃなくて美味しいお店予約しちゃうよぉ〜😍💌なんちゃって🤣💦"]

    static func offer(level: Int) -> [String] {
        switch level {
        case 1: return offer1
        case 2: return offer2
        case 3: return offer3
        case 4: return offer4
        default: return offer5
        }
    }

    static let closings = [
        "また連絡するねぇ〜💌💕",
        "返事待ってるねぇ〜😘❤️無理しないでねぇ〜🙏✨",
        "体に気をつけてねぇ〜💕風邪ひくなよぉ〜😟🙏",
        "おやすみ〜🌃✨いい夢見てねぇ〜😍💤",
        "今日も一日お疲れ様〜🍺✨{t}は偉いねぇ〜👏😊"
    ]

    static let kaomoji = [
        "(^^♪","(^_^;)","(≧▽≦)","(*^^*)","(^^ゞ",
        "(^o^)","(￣▽￣)","(´ε｀ )♥","(´∀｀*)","(^з^)-☆"
    ]

    static let katakanaMap: [(String, String)] = [
        ("ありがとう","アリガトウ"),("おはよう","オハヨウ"),("こんにちは","コンニチハ"),
        ("こんばんは","コンバンハ"),("お疲れ様","オツカレサマ"),("可愛い","カワイイ"),
        ("かわいい","カワイイ"),("綺麗","キレイ"),("きれい","キレイ"),
        ("すごい","スゴイ"),("凄い","スゴイ"),("よろしく","ヨロシク"),
        ("お願い","オネガイ"),("頑張","ガンバ"),("がんば","ガンバ"),
        ("大丈夫","ダイジョウブ"),("久しぶり","ヒサシブリ"),("誕生日","タンジョウビ"),
        ("おめでとう","オメデトウ"),("ごめん","ゴメン"),("了解","リョウカイ"),
        ("確認","カクニン"),("最高","サイコウ"),("美味しい","オイシイ"),
        ("おいしい","オイシイ"),("楽しい","タノシイ"),("たのしい","タノシイ"),
        ("嬉しい","ウレシイ"),("うれしい","ウレシイ"),("悲しい","カナシイ"),
        ("寂しい","サビシイ"),("さみしい","サビシイ")
    ]

    static let kimoText = ["","Lv.1 爽やか☀️","Lv.2 ほのぼの😊","Lv.3 クセ強め😅","Lv.4 かなりキモい😍","Lv.5 限界突破‼️🤣"]
    static let emojiText = ["","Lv.1 ひかえめ🌱","Lv.2 ふつう😊","Lv.3 多め💕","Lv.4 盛り盛り💕","Lv.5 爆盛り❤️😍✨"]
    static let shitagoText = ["","Lv.1 紳士的🙏","Lv.2 ほのめかし🍺","Lv.3 積極的😘","Lv.4 グイグイ💌","Lv.5 危険水域⚠️🤣"]
}

// MARK: - 時間帯
enum OjisanTimeMode: String, CaseIterable, Codable {
    case auto, morning, noon, night, none
    var label: String {
        switch self {
        case .auto: return "自動（今の時間）"
        case .morning: return "朝 ☀️"
        case .noon: return "昼 🍖"
        case .night: return "夜 🌃"
        case .none: return "挨拶なし"
        }
    }
}

// MARK: - 外観モード
enum OjisanAppearance: String, CaseIterable, Codable {
    case system, light, dark
    var label: String {
        switch self {
        case .system: return "システム連動"
        case .light: return "ライト固定"
        case .dark: return "ダーク固定"
        }
    }
}
