import Foundation

// MARK: - 天気・Wikipedia（キー不要・Web版と同一相手先）
struct WeatherNow: Sendable {
    let temp: Double
    let code: Int
    let wind: Double
    var japanese: String {
        switch code {
        case 0: return "快晴"
        case 1..<3: return "晴れ・曇り"
        case 3..<50: return "曇り"
        case 50..<80: return "雨"
        default: return "雷雨の可能性"
        }
    }
}

enum InfoClients {
    static func fetchWeather(lat: Double, lon: Double) async throws -> WeatherNow {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lon)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,wind_speed_10m"),
            URLQueryItem(name: "timezone", value: "Asia/Tokyo"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cur = json["current"] as? [String: Any],
              let t = cur["temperature_2m"] as? Double,
              let w = cur["weather_code"] as? Int,
              let s = cur["wind_speed_10m"] as? Double else {
            throw GeminiError.empty
        }
        return WeatherNow(temp: t, code: w, wind: s)
    }

    struct WikiSummary: Sendable {
        let title: String
        let extract: String
        let url: String
    }

    static func fetchWiki(_ word: String) async throws -> WikiSummary {
        let q = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
        let url = URL(string: "https://ja.wikipedia.org/api/rest_v1/page/summary/\(q)")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.empty
        }
        let title = (json["title"] as? String) ?? word
        let extract = (json["extract"] as? String) ?? "概要なし"
        var link = ""
        if let urls = json["content_urls"] as? [String: Any],
           let desktop = urls["desktop"] as? [String: Any],
           let page = desktop["page"] as? String {
            link = page
        }
        return WikiSummary(title: title, extract: extract, url: link)
    }
}
