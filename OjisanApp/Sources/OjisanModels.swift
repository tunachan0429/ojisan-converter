import Foundation

// MARK: - 履歴モデル（HTMLの localStorage ojisan_hist 互換＋お気に入り・検索用に拡張）
struct OjisanHistoryItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var time: Date = Date()
    var input: String
    var output: String
    var preset: String
    var score: Int
    var isFavorite: Bool = false
}

struct OjisanResult: Identifiable, Hashable {
    var id = UUID()
    var title: String
    var badge: String
    var isHot: Bool
    var text: String
}
