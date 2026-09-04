import SwiftUI

@main
struct AssistantApp: App {
    @State private var settings: SettingsStore
    @State private var chat: ChatStore
    @State private var reminders: ReminderStore

    init() {
        let s = SettingsStore()
        _settings = State(initialValue: s)
        _chat = State(initialValue: ChatStore(settings: s))
        _reminders = State(initialValue: ReminderStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .environment(chat)
                .environment(reminders)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            ChatView()
                .tabItem { Label("チャット", systemImage: "message") }
            RemindView()
                .tabItem { Label("リマインド", systemImage: "bell") }
            InfoView()
                .tabItem { Label("情報", systemImage: "magnifyingglass") }
            CreateView()
                .tabItem { Label("作成", systemImage: "square.and.pencil") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
