import Foundation

// MARK: - Gemini連携（HTMLの自動フォールバック chain 移植）
// 選択モデル → 2.5-flash → 2.0-flash-lite → 2.0-flash → 1.5-flash の順で逃がす。503/500/429/502のみリトライ。
enum OjisanGeminiError: Error, LocalizedError {
    case noKey
    case empty(model: String)
    case http(Int, String, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noKey: return "APIキーがありません"
        case .empty(let m): return "空の応答でした (\(m))"
        case .http(let code, let body, let model):
            return "Geminiエラー \(code) [\(model)]: \(String(body.prefix(200)))"
        case .network(let m): return m
        }
    }

    var status: Int {
        switch self {
        case .http(let c, _, _): return c
        case .empty: return 502
        case .noKey: return 0
        case .network: return -1
        }
    }

    var model: String {
        switch self {
        case .http(_, _, let m): return m
        case .empty(let m): return m
        default: return ""
        }
    }
}

enum OjisanGemini {
    static func fetchOnce(model: String, key: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)") else {
            throw OjisanGeminiError.network("URL不正")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.9, "maxOutputTokens": 800]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError {
            throw OjisanGeminiError.network("ネット接続を確認してねぇ〜🥺💦 (\(e.code.rawValue))")
        }
        guard let http = resp as? HTTPURLResponse else {
            throw OjisanGeminiError.network("通信に失敗したよぉ〜🥺💦")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OjisanGeminiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "", model)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = json["candidates"] as? [[String: Any]],
              let cand = cands.first,
              let content = cand["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw OjisanGeminiError.empty(model: model)
        }
        let text = parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw OjisanGeminiError.empty(model: model) }
        return text
    }

    static func friendly(_ e: Error) -> String {
        guard let g = e as? OjisanGeminiError else { return String(describing: e).prefix(200).description }
        switch g {
        case .http(let c, _, let m) where c == 503:
            return "混雑中だよぉ〜🥺💦 [\(m) 503] Google側がパンク中。1分待って再試行か、モデルを変えてねぇ〜🙏"
        case .http(let c, _, let m) where c == 429:
            return "回数制限だよぉ〜🥺💦 [\(m) 429] 分速/日次の上限。1〜2分待ってねぇ〜⏳"
        case .http(let c, _, let m) where c == 404:
            return "モデル名が違うよぉ〜🥺💦 [\(m) 404] モデル選択を安定版に変えてねぇ〜🙏"
        case .http(let c, _, _) where c == 400:
            return "リクエスト不正だよぉ〜🥺💦 [400] 文章が長すぎかも。短くして再試行してねぇ〜✂️"
        case .http(let c, _, _) where c == 403 || c == 401:
            return "キー無効だよぉ〜🥺💦 [\(c)] APIキーを作り直して保存し直してねぇ〜🔑"
        default:
            return g.errorDescription ?? "変換に失敗したよぉ〜🥺💦"
        }
    }

    static func convert(raw: String, options: OjisanOptions, firstModel: String, key: String) async throws -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw OjisanGeminiError.noKey }
        // 動作確認済みchain（2026-09実測: 3.6-flash推奨・旧2.x/1.5は新規ユーザーに404）
        var chain = [firstModel, "gemini-3.6-flash", "gemini-flash-latest", "gemini-3.5-flash", "gemini-3.5-flash-lite", "gemini-flash-lite-latest"]
        // 重複除去（順序保持）
        var seen = Set<String>()
        chain = chain.filter { seen.insert($0).inserted }
        let prompt = OjisanEngine.buildGeminiPrompt(raw: raw, o: options)
        var lastErr: Error = OjisanGeminiError.network("不明なエラー")
        for model in chain {
            for attempt in 1...2 {
                do {
                    return try await fetchOnce(model: model, key: trimmed, prompt: prompt)
                } catch {
                    lastErr = error
                    let status = (error as? OjisanGeminiError)?.status ?? -1
                    let retryable = (status == 503 || status == 500 || status == 429 || status == 502)
                    if retryable && attempt < 2 {
                        let wait = UInt64((1000 * attempt + Int.random(in: 0...800)) * 1_000_000)
                        try? await Task.sleep(nanoseconds: wait)
                        continue
                    }
                    break
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        throw lastErr
    }
}
