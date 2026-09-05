import Foundation

// MARK: - ローカル高精度エンジン（ojisan-converter.html 完全移植・Swift版）
// JSの mulberry32 / burst / maybeKaomoji / ojiTransformSentence / localConvert / kimoScore を等価移植。

struct OjisanOptions: Codable {
    var target: String = "ゆみちゃん"
    var me: String = "おじさん"
    var timeMode: OjisanTimeMode = .auto
    var activePreset: String = "王道"
    var kimo: Int = 4
    var emojiLevel: Int = 4
    var shitago: Int = 2
    var useAisatsu: Bool = true
    var useHome: Bool = true
    var useKinkyo: Bool = true
    var useOffer: Bool = true
    var useKaomoji: Bool = true
    var useKatakana: Bool = true
    var useBikuri: Bool = true
    var useShime: Bool = true
    var emojiEnabled: [String] = OjisanData.emojiAll
}

// MARK: - 決定的乱数（mulberry32互換・JS完全等価）
struct SeededRNG: RandomNumberGenerator {
    private var a: UInt32
    init(seed: UInt32) { self.a = seed }
    private mutating func nextUInt32() -> UInt32 {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return t ^ (t >> 14)
    }
    mutating func next() -> UInt64 {
        let x = nextUInt32()
        return (UInt64(x) << 32) | UInt64(x ^ 0x9E3779B9)
    }
    mutating func nextDouble() -> Double {
        Double(nextUInt32()) / 4294967296.0
    }
}

enum OjisanEngine {
    // MARK: - 基本操作
    static func pick<T>(_ arr: [T], _ rng: inout SeededRNG) -> T {
        let d = rng.nextDouble()
        let i = min(arr.count - 1, max(0, Int(d * Double(arr.count))))
        return arr[i]
    }

    static func enabledEmojis(_ o: OjisanOptions) -> [String] {
        o.emojiEnabled.isEmpty ? ["❤️", "😍", "✨"] : o.emojiEnabled
    }

    static func burst(_ rng: inout SeededRNG, level: Int, pool: [String]) -> String {
        let d = rng.nextDouble()
        let n = max(1, Int((Double(level) * (0.6 + d * 0.9)).rounded()))
        var s = ""
        for _ in 0..<n {
            var r = rng
            s += pick(pool, &r)
            rng = r
        }
        return s
    }

    static func maybeKaomoji(_ rng: inout SeededRNG, prob: Double, use: Bool) -> String {
        guard use else { return "" }
        if rng.nextDouble() < prob {
            return " " + pick(OjisanData.kaomoji, &rng)
        }
        return ""
    }

    static func fill(_ s: String, target: String, me: String) -> String {
        s.replacingOccurrences(of: "{t}", with: target)
            .replacingOccurrences(of: "{me}", with: me)
    }

    // MARK: - 1文変換
    static func transformSentence(_ s: String, o: OjisanOptions, rng: inout SeededRNG) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let pool = enabledEmojis(o)

        if o.useKatakana {
            for (k, v) in OjisanData.katakanaMap {
                t = t.replacingOccurrences(of: k, with: v)
            }
        }

        // 末尾の 。！？!?…～〜ー を剥がす
        let punctSet = CharacterSet(charactersIn: "。！？!?…～〜ー")
        var endPunct = ""
        while let last = t.unicodeScalars.last, punctSet.contains(last) {
            endPunct = String(last) + endPunct
            t = String(t.dropLast())
        }

        // 語尾ルール（JSと同順・inout捕捉回避のためデータ化）
        // (suffix, base, kaoProb)
        let rules: [(String, String, Double)] = [
            ("お願いします", "オネガイしますねぇ〜🙏", 0),
            ("よろしくお願いします", "ヨロシクねぇ〜😘", 0),
            ("してください", "してねぇ〜😘", 0),
            ("しましょう", "しましょうねぇ〜😍", 0.4),
            ("ましょう", "ましょうねぇ〜😍", 0.4),
            ("ですよね", "ですよねぇ〜😊", 0),
            ("ますよね", "ますよねぇ〜😊", 0),
            ("でした", "だったよぉ〜😊", 0.3),
            ("ました", "ましたよぉ〜😊", 0.3),
            ("です", "ですよぉ〜😘", 0),
            ("ます", "ますよぉ〜💕", 0),
            ("だね", "だねぇ〜😍", 0),
            ("だよ", "だよぉ〜😘", 0),
            ("かな", "かなぁ〜🥺", 0),
            ("よね", "よねぇ〜😊", 0),
            ("よ", "よぉ〜😍", 0),
            ("ね", "ねぇ〜💕", 0),
        ]

        var hit = false
        for (suffix, base, kaoProb) in rules {
            if t.hasSuffix(suffix) {
                let e = burst(&rng, level: o.emojiLevel, pool: pool)
                let k = maybeKaomoji(&rng, prob: kaoProb, use: o.useKaomoji)
                t = String(t.dropLast(suffix.count)) + base + e + k
                hit = true
                break
            }
        }
        if !hit {
            // ?系
            if t.hasSuffix("?") || t.hasSuffix("？") || t.hasSuffix("の?") {
                if t.hasSuffix("の?") {
                    t = String(t.dropLast(2)) + "のぉ〜❓" + burst(&rng, level: o.emojiLevel, pool: pool)
                } else {
                    t = String(t.dropLast()) + "〜❓" + burst(&rng, level: o.emojiLevel, pool: pool)
                }
                hit = true
            } else if t.hasSuffix("!") || t.hasSuffix("！") {
                t = String(t.dropLast()) + "‼️" + burst(&rng, level: o.emojiLevel, pool: pool)
                hit = true
            }
        }
        if !hit {
            if t.count <= 6 {
                t = t + "だよぉ〜😍" + burst(&rng, level: o.emojiLevel, pool: pool) + maybeKaomoji(&rng, prob: 0.35, use: o.useKaomoji)
            } else if t.hasSuffix("った") || t.hasSuffix("いた") || t.hasSuffix("きた") || t.hasSuffix("した") {
                t = t + "よぉ〜😊" + burst(&rng, level: o.emojiLevel, pool: pool) + maybeKaomoji(&rng, prob: 0.3, use: o.useKaomoji)
            } else {
                t = t + "だよぉ〜😘" + burst(&rng, level: o.emojiLevel, pool: pool) + maybeKaomoji(&rng, prob: 0.35, use: o.useKaomoji)
            }
            if endPunct.contains("?") || endPunct.contains("？") {
                t += "❓" + burst(&rng, level: o.emojiLevel, pool: pool)
            }
        }

        // ！？乱用
        if o.useBikuri && rng.nextDouble() < 0.25 + Double(o.kimo) * 0.08 {
            t += "‼️" + burst(&rng, level: max(1, o.emojiLevel - 2), pool: pool)
        }
        // 読点をウザく
        if rng.nextDouble() < 0.2 + Double(o.kimo) * 0.08 {
            t = t.replacingOccurrences(of: "、", with: "、" + burst(&rng, level: 1, pool: pool))
        }
        // 伸ばし
        if rng.nextDouble() < 0.15 + Double(o.kimo) * 0.05 {
            t = t.replacingOccurrences(of: "ー", with: "〜")
        }
        if o.useKatakana && rng.nextDouble() < 0.2 {
            t = t.replacingOccurrences(of: "ない", with: "ナイ")
                .replacingOccurrences(of: "たい", with: "タイ")
        }
        return t
    }

    // MARK: - 全文変換
    static func localConvert(raw: String, o: OjisanOptions, seed: UInt32) -> String {
        var rng = SeededRNG(seed: seed)
        let target = o.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ちゃん" : o.target.trimmingCharacters(in: .whitespacesAndNewlines)
        let me = o.me.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "おじさん" : o.me.trimmingCharacters(in: .whitespacesAndNewlines)

        var input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { input = "こんにちは。元気にしてる？" }

        // 段落→文に分割
        let paras = input.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var sentences: [String] = []
        for p in paras {
            // 。！？!? の後で分割（JSの (?<=[。！？!?]) 互換）
            var cur = ""
            for ch in p {
                cur.append(ch)
                if "。！？!?".contains(ch) {
                    let s = cur.trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { sentences.append(s) }
                    cur = ""
                }
            }
            let rest = cur.trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { sentences.append(rest) }
            if p.isEmpty { sentences.append(p) }
        }
        if sentences.isEmpty { sentences = [input] }

        var body: [String] = []
        for s in sentences {
            var one = s
            while one.hasSuffix("。") { one = String(one.dropLast()) }
            body.append(transformSentence(one, o: o, rng: &rng))
        }

        var out: [String] = []
        let pool = enabledEmojis(o)

        if o.useAisatsu && o.timeMode != .none {
            var key = o.timeMode
            if key == .auto {
                let h = Calendar.current.component(.hour, from: Date())
                key = h < 10 ? .morning : (h < 17 ? .noon : .night)
            }
            let greetPool: [String]
            switch key {
            case .morning: greetPool = OjisanData.greetMorning
            case .night: greetPool = OjisanData.greetNight
            default: greetPool = OjisanData.greetNoon
            }
            let g = fill(pick(greetPool, &rng), target: target, me: me)
            let w = fill(pick(OjisanData.weather, &rng), target: target, me: me)
            out.append("\(g)\(burst(&rng, level: o.emojiLevel, pool: pool))\(w)\(burst(&rng, level: o.emojiLevel, pool: pool))\(maybeKaomoji(&rng, prob: 0.5, use: o.useKaomoji))")
            if rng.nextDouble() < 0.7 {
                out.append(fill(pick(OjisanData.compliments, &rng), target: target, me: me) + maybeKaomoji(&rng, prob: 0.4, use: o.useKaomoji))
            }
        } else if o.useHome && rng.nextDouble() < 0.85 {
            out.append(fill(pick(OjisanData.compliments, &rng), target: target, me: me) + maybeKaomoji(&rng, prob: 0.4, use: o.useKaomoji))
        }

        for (i, s) in body.enumerated() {
            out.append(s)
            if o.useKinkyo && body.count >= 1 && i == body.count / 2 && rng.nextDouble() < 0.3 + Double(o.kimo) * 0.12 {
                out.append("ところでねぇ〜😊" + fill(pick(OjisanData.kinkyo, &rng), target: target, me: me) + maybeKaomoji(&rng, prob: 0.4, use: o.useKaomoji))
            }
            if o.useHome && body.count > 2 && i == 0 && rng.nextDouble() < 0.5 {
                out.append(fill(pick(OjisanData.compliments, &rng), target: target, me: me))
            }
        }

        if o.useOffer && rng.nextDouble() < 0.35 + Double(o.shitago) * 0.13 {
            let lvl = min(5, max(1, o.shitago + (rng.nextDouble() < 0.3 ? 1 : 0)))
            out.append(fill(pick(OjisanData.offer(level: lvl), &rng), target: target, me: me) + maybeKaomoji(&rng, prob: 0.45, use: o.useKaomoji))
        }
        if o.useShime {
            out.append(fill(pick(OjisanData.closings, &rng), target: target, me: me) + burst(&rng, level: o.emojiLevel, pool: pool) + maybeKaomoji(&rng, prob: 0.5, use: o.useKaomoji))
        }
        if o.activePreset == "メンヘラ" && rng.nextDouble() < 0.8 {
            out.append("あ、返事は急がなくて大丈夫だよぉ〜(^_^;)💦でも待ってるねぇ〜🥺💕\(burst(&rng, level: 2, pool: pool))")
        }
        if o.activePreset == "昭和" {
            out.append("ではでは、失礼しまぁ〜す(^^ゞ \(burst(&rng, level: 1, pool: pool))")
        }
        return out.joined(separator: "\n")
    }

    // MARK: - スコア
    struct KimoReport {
        var score: Int
        var emojiCount: Int
        var kaoCount: Int
        var rank: String
    }

    static func kimoScore(text: String, o: OjisanOptions) -> KimoReport {
        // 絵文字数：Emojiプロパティ＋おじさん定番記号
        var emojiCount = 0
        for scalar in text.unicodeScalars {
            if scalar.properties.isEmoji { emojiCount += 1 }
        }
        // ❤️系のVS16重複をざっくり補正（多めに出る分はスコア上限で吸収）
        let kaoKeys = ["(^^", "(´", "(≧", "♥", "☆", "(￣", "(^"]
        var kao = 0
        for k in kaoKeys { kao += text.components(separatedBy: k).count - 1 }
        let raw = 18 + o.kimo * 9 + o.emojiLevel * 6 + min(25, Int(Double(emojiCount) * 0.5)) + Int(Double(kao) * 1.5)
        let score = min(100, raw)
        let rank: String
        switch score {
        case 85...: rank = "限界突破級 ‼️🤣💕"
        case 65...: rank = "ベテランおじさん 😍🍺"
        case 40...: rank = "駆け出しおじさん 😊✨"
        default: rank = "まだ爽やか ☀️🌱"
        }
        return KimoReport(score: score, emojiCount: emojiCount, kaoCount: kao, rank: rank)
    }

    // MARK: - Geminiプロンプト（HTML同一）
    static func buildGeminiPrompt(raw: String, o: OjisanOptions) -> String {
        let preset = OjisanData.presets.first(where: { $0.id == o.activePreset })
        let presetName = preset?.name ?? "👑 王道おじさん"
        let presetDesc = preset?.desc ?? "THE おじさん構文"
        var parts: [String] = []
        if o.useAisatsu { parts.append("時間帯の挨拶＋天気の話") }
        if o.useHome { parts.append("褒め言葉") }
        if o.useKinkyo { parts.append("おじさんの近況報告") }
        if o.useOffer { parts.append("ご飯・お茶・ドライブのお誘い") }
        if o.useShime { parts.append("返信催促つき締めの言葉") }
        let include = parts.joined(separator: "、")
        let kao = o.useKaomoji ? "顔文字 (^^♪ (^_^;) (≧▽≦) を使う" : "顔文字は使わない"
        let kata = o.useKatakana ? "「アリガトウ」「カワイイ」「ヨロシク」など一部カタカナ化する" : "カタカナ化は控えめ"
        return """
        あなたは「おじさん構文」のプロ翻訳家です。以下の普通の日本語メッセージを、気持ち悪いおじさん構文（おじさんLINE）に変換してください。

        【絶対ルール】
        - 絵文字を大量に使う（量レベル\(o.emojiLevel)/5。ハート❤️💕😍😘✨🌸☀️🍺🙏💦‼️などを文末・文中に自然に散りばめる）
        - 語尾は「〜だよぉ😘💕」「〜ねぇ〜✨」「〜かなぁ〜🥺💦」「〜ですよぉ🙏✨」のように伸ばす
        - 一人称は「\(o.me)」、相手は「\(o.target)」と呼ぶ
        - プリセットは「\(presetName)：\(presetDesc)」、キモさ\(o.kimo)/5、下心\(o.shitago)/5
        - 含める要素：\(include)
        - \(kao)
        - \(kata)
        - 元の文章の用件・日時・依頼・謝罪・名前などの情報は1つ残らずすべて盛り込む。省略・要約は厳禁
        - 出力は必ず元の文章より長くする。短くまとめない。元の文が短くても挨拶・褒め・近況・お誘い・締めで膨らませる
        - 元の意味は変えない
        - 出力は変換後の文章のみ。解説・前置きは書かない

        【変換する文章】
        \(raw)
        """
    }
}
