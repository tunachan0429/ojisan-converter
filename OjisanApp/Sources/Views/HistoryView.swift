import SwiftUI

// MARK: - ④履歴タブ（無制限化＋検索＋お気に入り：今回の追加機能）
struct HistoryView: View {
    @Environment(OjisanStore.self) private var store
    @State private var showClear = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 検索バー
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("履歴を検索（入力・結果）", text: Binding(get: { store.historyQuery }, set: { store.historyQuery = $0 }))
                        .textFieldStyle(.plain)
                    if !store.historyQuery.isEmpty {
                        Button { store.historyQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 10)

                HStack {
                    Toggle("⭐ お気に入りのみ", isOn: Binding(get: { store.showFavoritesOnly }, set: { store.showFavoritesOnly = $0 }))
                        .font(.caption).bold().tint(OjisanTheme.accent)
                    Spacer()
                    Text("\(store.filteredHistory.count)/\(store.history.count)件")
                        .font(.caption).bold().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if store.filteredHistory.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Text("🕒").font(.largeTitle)
                        Text(store.history.isEmpty ? "履歴はまだないよぉ〜🥺" : "見つからなかったよぉ〜🥺").bold()
                        Text("変換するとここに無制限で溜まるよぉ〜💕").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(store.filteredHistory) { item in
                            historyRow(item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { store.deleteHistory(item.id) } label: { Label("削除", systemImage: "trash") }
                                }
                                .swipeActions(edge: .leading) {
                                    Button { store.toggleFavorite(item.id) } label: { Label(item.isFavorite ? "外す" : "お気に", systemImage: item.isFavorite ? "star.slash" : "star") }
                                    .tint(.orange)
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .ojisanBackground()
            .navigationTitle("履歴・お気に入り 🕒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !store.history.isEmpty {
                    Button("全消去", role: .destructive) { showClear = true }
                }
            }
            .confirmationDialog("履歴を全部消しますか？", isPresented: $showClear, titleVisibility: .visible) {
                Button("消す", role: .destructive) { store.clearHistory() }
                Button("やめる", role: .cancel) {}
            }
        }
    }

    private func historyRow(_ item: OjisanHistoryItem) -> some View {
        Button {
            store.restore(item)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        store.toggleFavorite(item.id)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(item.isFavorite ? .orange : .secondary)
                    }
                    .buttonStyle(.plain)
                    Text(String(item.output.prefix(50)) + (item.output.count > 50 ? "…" : ""))
                        .font(.subheadline).bold()
                        .lineLimit(2)
                }
                Text("元: \(String(item.input.prefix(60)))…")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.time, style: .date).font(.caption2).foregroundStyle(.secondary)
                    Text("•").font(.caption2).foregroundStyle(.secondary)
                    Text("🎭 \(item.preset)").font(.caption2).bold().foregroundStyle(.secondary)
                    Text("•").font(.caption2).foregroundStyle(.secondary)
                    Text("📊 \(item.score)点").font(.caption2).bold().foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
