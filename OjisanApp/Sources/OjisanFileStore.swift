import Foundation

// MARK: - Ojisan専用ファイル保存（NativeAppと競合しないよう別名）
enum OjisanFileStore {
    private static func directory() throws -> URL {
        let fm = FileManager.default
        return try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    static func load<T: Decodable>(_ type: T.Type, name: String, default defaultValue: T) -> T {
        do {
            let url = try directory().appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(T.self, from: data)
        } catch {
            return defaultValue
        }
    }

    static func save<T: Encodable>(_ value: T, name: String) {
        do {
            let url = try directory().appendingPathComponent(name)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            // 保存失敗は無視
        }
    }
}
