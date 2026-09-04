import Foundation

// MARK: - Gemini API通信（Web版と同一仕様・camelCase公式形式）
enum GeminiError: Error, LocalizedError {
    case noKey
    case empty
    case http(Int, String)
    case network

    var errorDescription: String? {
        switch self {
        case .noKey: return "NO_KEY"
        case .empty: return "空応答"
        case .http(let code, let body): return "Gemini \(code): \(String(body.prefix(200)))"
        case .network: return "ネット接続を確認してください"
        }
    }
}

struct GeminiImage: Sendable {
    let mime: String
    let base64: String
}

struct GeminiResult: Sendable {
    let text: String
    let sources: [Source]
    let grounded: Bool
    let model: String
    let engineLabel: String
}

struct HistoryItem: Sendable {
    let role: Role
    let text: String
}

enum GeminiClient {
    static func generate(system: String,
                         userText: String,
                         history: [HistoryItem] = [],
                         images: [GeminiImage] = [],
                         engine: EngineKey,
                         search: SearchMode,
                         summary: String = "",
                         callerName: String = "",
                         apiKey: String) async throws -> GeminiResult {
        guard !apiKey.isEmpty else { throw GeminiError.noKey }
        guard let spec = AIConfig.engines[engine] else { throw GeminiError.empty }

        var fullSystem = system
        if !summary.isEmpty { fullSystem += "\n【これまでの要約】\n\(summary)" }
        if !callerName.isEmpty { fullSystem += " 話者は「\(callerName)」。"; }

        var contents: [[String: Any]] = []
        for h in history.suffix(8) {
            contents.append([
                "role": h.role == .user ? "user" : "model",
                "parts": [["text": h.text]]
            ])
        }
        var userParts: [[String: Any]] = []
        if !userText.isEmpty { userParts.append(["text": userText]) }
        for im in images {
            userParts.append(["inlineData": ["mimeType": im.mime, "data": im.base64]])
        }
        contents.append(["role": "user", "parts": userParts])

        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": fullSystem]]],
            "contents": contents,
            "generationConfig": [
                "temperature": spec.temperature,
                "maxOutputTokens": spec.maxTokens
            ]
        ]
        let useSearch = search != .off
        if useSearch { body["tools"] = [["google_search": [String: Any]()]] }

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(spec.model):generateContent?key=\(apiKey)")!
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let fallbackData: Data? = useSearch ? try JSONSerialization.data(withJSONObject: stripTools(body)) : nil
        do {
            return try await post(url: url, body: bodyData, engine: spec, search: search, fallbackBody: fallbackData)
        } catch let e as URLError {
            throw mapURLError(e)
        }
    }

    // 軽量・検索なし（連絡文・ToDo・要約などの枠節約用）
    static func generateLight(system: String, userText: String, apiKey: String) async throws -> String {
        let r = try await generate(system: system, userText: userText,
                                  engine: .light, search: .off, apiKey: apiKey)
        return r.text
    }

    private static func stripTools(_ body: [String: Any]) -> [String: Any] {
        var b = body
        b.removeValue(forKey: "tools")
        if var gc = b["generationConfig"] as? [String: Any] {
            gc["temperature"] = 0.8
            b["generationConfig"] = gc
        }
        return b
    }

    private static func post(url: URL, body: Data, engine: EngineSpec,
                             search: SearchMode, fallbackBody: Data?) async throws -> GeminiResult {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GeminiError.network }
        if http.statusCode == 400, let fb = fallbackBody {
            var req2 = URLRequest(url: url)
            req2.httpMethod = "POST"
            req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req2.httpBody = fb
            let (data2, resp2) = try await URLSession.shared.data(for: req2)
            return try parse(data: data2, response: resp2, engine: engine, usedSearch: false)
        }
        return try parse(data: data, response: resp, engine: engine, usedSearch: search != .off)
    }

    private static func parse(data: Data, response: URLResponse, engine: EngineSpec, usedSearch: Bool) throws -> GeminiResult {
        guard let http = response as? HTTPURLResponse else { throw GeminiError.network }
        guard (200..<300).contains(http.statusCode) else {
            throw GeminiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cands = json["candidates"] as? [[String: Any]],
              let cand = cands.first else { throw GeminiError.empty }
        var text = ""
        if let content = cand["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !text.isEmpty else { throw GeminiError.empty }
        var sources: [Source] = []
        if let meta = cand["groundingMetadata"] as? [String: Any],
           let chunks = meta["groundingChunks"] as? [[String: Any]] {
            for ch in chunks {
                if let web = ch["web"] as? [String: Any],
                   let uri = web["uri"] as? String,
                   !sources.contains(where: { $0.uri == uri }) {
                    sources.append(Source(title: (web["title"] as? String) ?? uri, uri: uri))
                }
            }
        }
        return GeminiResult(text: text, sources: sources,
                            grounded: !sources.isEmpty || usedSearch,
                            model: engine.model, engineLabel: engine.label)
    }

    private static func mapURLError(_ e: URLError) -> GeminiError {
        switch e.code {
        case .notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .networkConnectionLost, .dnsLookupFailed:
            return .network
        default:
            return .http(-1, e.localizedDescription)
        }
    }
}
