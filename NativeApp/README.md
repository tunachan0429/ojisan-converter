# アシスタント Native版（SwiftUI）

Web版（`www/index.html`）と同機能・同UI方針の純正iOSアプリ。
Capability差分は正直にここに書く。

## 構成

```
NativeApp/
  project.yml                 XcodeGen定義（.xcodeprojは生成物・git管理外）
  Sources/
    AssistantApp.swift        @main / TabView
    AIConfig.swift            用途別ルーター・モード・テンプレ・定型文
    Models.swift              Codableモデル
    Persistence.swift         JSONファイル保存
    GeminiClient.swift        Gemini API通信（検索連携・Vision・要約）
    InfoClients.swift         天気・Wikipedia
    Stores.swift              設定・チャット・リマインダー（通知予約含む）
    VoiceInput.swift          音声認識（Speech）
    Views/
      ChatView.swift
      RemindView.swift
      InfoView.swift
      CreateView.swift
      SettingsView.swift
  README.md                   このファイル
```

- 言語: Swift 5 / SwiftUI / Observation（`@Observable`）
- 対象: iOS 17.0+ / iPhone（`TARGETED_DEVICE_FAMILY=1`）
- Bundle ID: `com.my.bannou.native`（Web版と別なので上書きしない）
- 永続化: Application Support内のJSON（画像バイナリは保存しない）
- 署名: なし（GitHub ActionsのMacでビルド→Sideloadly/AltStoreで7日署名）

## ビルド（自動）

1. `git push`（`NativeApp/**` に変更があれば自動実行）
2. GitHub → Actions → `Build Native IPA` → Artifactsの `Assistant-unsigned-ipa` をDL
   または Releaseの `native-unsigned` から直DL
3. Sideloadlyで無料Apple ID署名→iPhoneに転送→設定で信頼

## Web版との差分（正直版）

- 良くなる: アプリを閉じていてもリマインダー通知が届く / 音声入力が使える / 動きが軽い
- 同じ: チャット・検索連携・出典・画像認識・天気・Wikipedia・連絡文・アイデア・設定・バックアップ
- まだない: 画像生成タブ（Web版にもないので同等）

## 注意

- Windows上ではiOSビルド不可。構文検証はActionsログで確認すること
- `NativeApp/*.xcodeproj` と `NativeApp/build/` は生成物のためgit管理外
