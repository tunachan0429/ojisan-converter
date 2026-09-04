import Foundation

// MARK: - チャット
enum Role: String, Codable, Sendable {
    case user, ai
}

struct Source: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var uri: String
}

struct ChatMessage: Codable, Identifiable, Sendable {
    var id = UUID()
    var role: Role
    var text: String
    var time: Date
    var sources: [Source] = []
    var follow: [String] = []
    var engine: String = ""
    var isError: Bool = false
    var pendingText: String? = nil
}

struct ChatThread: Codable, Identifiable, Sendable {
    var id = UUID()
    var mode: String = "all"
    var title: String = "はじめて"
    var summary: String = ""
    var summaryCount: Int = 0
    var messages: [ChatMessage] = []
}

// MARK: - リマインダー
enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case none, daily, weekly
    var label: String {
        switch self {
        case .none: return "なし"
        case .daily: return "毎日"
        case .weekly: return "毎週"
        }
    }
}

struct ReminderItem: Codable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var when: Date
    var repeatMode: RepeatMode = .none
    var memo: String = ""
    var done: Bool = false
    var notifID: String? = nil
}

// MARK: - バックアップ
struct Backup: Codable, Sendable {
    var threads: [ChatThread]
    var reminders: [ReminderItem]
    var exported: Date
}
