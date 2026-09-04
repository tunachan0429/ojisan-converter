import SwiftUI

// MARK: - リマインド（本物のローカル通知付き）
struct RemindView: View {
    @Environment(ReminderStore.self) private var reminders
    @Environment(ChatStore.self) private var chat

    @State private var title = ""
    @State private var when = Date().addingTimeInterval(3600)
    @State private var repeatMode: RepeatMode = .none
    @State private var memo = ""
    @State private var notice = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("新しく登録") {
                    TextField("やること", text: $title)
                    DatePicker("日時", selection: $when, in: Date()...)
                    Picker("繰り返し", selection: $repeatMode) {
                        ForEach(RepeatMode.allCases, id: \.self) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("メモ（任意）", text: $memo)
                    HStack {
                        Button("登録する") { add() }
                            .buttonStyle(.borderedProminent)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                        Button("通知を許可") {
                            Task {
                                let ok = await reminders.requestAuthorization()
                                notice = ok ? "通知を許可しました" : "設定で通知を許可してください"
                            }
                        }
                    }
                    if !notice.isEmpty {
                        Text(notice).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("登録済み") {
                    if reminders.items.isEmpty {
                        Text("まだ登録なし。忘れがちなことを入れとこう。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(reminders.items.sorted(by: { $0.when < $1.when })) { r in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title)
                                        .strikethrough(r.done)
                                        .foregroundStyle(r.done ? .secondary : .primary)
                                    Text("\(r.when, format: .dateTime.month().day().hour().minute())・\(r.repeatMode.label)\(r.memo.isEmpty ? "" : "・\(r.memo)")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(r.done ? "戻す" : "完了") { reminders.toggleDone(r.id) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            .listRowBackground(r.done ? nil : (r.when <= Date() ? Color.red.opacity(0.08) : nil))
                        }
                        .onDelete { idx in
                            let sorted = reminders.items.sorted(by: { $0.when < $1.when })
                            for i in idx { reminders.remove(sorted[i].id) }
                        }
                    }
                }
            }
            .navigationTitle("リマインド")
        }
    }

    private func add() {
        reminders.add(title: title.trimmingCharacters(in: .whitespaces),
                      when: when, repeatMode: repeatMode, memo: memo)
        title = ""
        memo = ""
    }
}
