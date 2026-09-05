# オジサン翻訳機 Native版（SwiftUI・5タブ）

`ojisan-converter.html` と同機能・同見た目の純正iOSアプリ。サイトは使わない。
スマホ用タブUI＋少しだけ機能増し。APIキーはコード埋め込み。

## 構成

```
OjisanApp/
  project.yml                 XcodeGen定義（.xcodeprojは生成物・git管理外）
  Sources/
    OjisanApp.swift           @main / 5タブ TabView＋トースト＋共有/読み上げ共通
    OjisanConfig.swift        埋め込みキー・プリセット・絵文字・例文データ
    OjisanEngine.swift        ローカル高精度エンジン（HTML完全移植）
    OjisanGemini.swift        Gemini連携（自動フォールバックchain）
    OjisanStore.swift         中央状態・履歴/お気に入り・設定永続化
    OjisanTheme.swift         HTML配色移植＋ダークモード
    OjisanModels.swift        履歴・結果モデル
    OjisanFileStore.swift     JSON保存（NativeAppと別名）
    Views/
      ConvertView.swift       ①変換（入力＋設定＋例文）
      ResultView.swift        ②結果（3案・コピー/共有/X/LINE/読み上げ）
      LinePreviewView.swift   ③LINE・分析（プレビュー＋キモさスコア）
      HistoryView.swift       ④履歴（無制限・検索・お気に入り）★追加機能
      OjisanSettingsView.swift ⑤設定（キー・外観・例文・FAQ）★ダークモード
    Support/Info.plist
    Assets.xcassets/          アイコン（NativeAppから流用）
```

- 言語: Swift 5 / SwiftUI / Observation（`@Observable`）
- 対象: iOS 17.0+ / iPhone（`TARGETED_DEVICE_FAMILY=1`）
- Bundle ID: `com.my.bannou.ojisan`（既存と別なので上書きしない）
- 永続化: Application Support内JSON＋UserDefaults（履歴500件・設定・累計）
- 署名: なし（GitHub ActionsのMacでビルド→Sideloadly/AltStoreで7日署名）

## タブ（希望の5タブ）

1. 変換：入力・相手/自分・時間帯・プリセット6種・スライダー3種・トグル8種・絵文字ON/OFF・変換バー・例文
2. 結果：3案同時表示（👑本命ローカル＋🤖Gemini案＋🎲別パターン）・全部コピー・共有シート・X投稿・LINE共有・読み上げ
3. LINE：LINE風プレビュー＋キモさ分析レポート（スコアバー・絵文字数・ランク）
4. 履歴：無制限（上限500）・検索・お気に入り絞り込み・スワイプ削除・タップ復元 ★追加
5. 設定：外観（ダークモード）・例文・使い方・FAQ・データ管理（APIの表示はなし・キーはコード埋め込みのみ）

## APIキー埋め込み（1箇所だけ）

`OjisanApp/Sources/OjisanConfig.swift`:

```swift
static let embeddedGeminiKey: String = ""
```

ここに `AIza...` を貼るだけ（実機検証済みの3.6-flash体系）。空なら設定タブ入力なしでもローカル変換で動作。
設定タブに入力欄はなく、一般ユーザーにはキーの存在を見せない設計。Git公開時は空推奨（抜き出し可能のため個人利用前提）。

モデルchain（2026-09実測で動作確認）：選択 → `gemini-3.6-flash` → `gemini-flash-latest` → `gemini-3.5-flash` → `gemini-3.5-flash-lite` → `gemini-flash-lite-latest`。旧2.x/1.5系は新規ユーザー向けに提供終了（404）のため除外。503/500/429/502のみリトライ→次モデルへ。

## ビルド（自動）

1. `git push`（`OjisanApp/**` に変更があれば自動実行）
2. GitHub → Actions → `Build Ojisan IPA` → Artifactsの `Ojisan-unsigned-ipa` をDL
   または Releaseの `ojisan-unsigned` から直DL
3. Sideloadlyで無料Apple ID署名→iPhoneに転送→設定で信頼

手動（Macのみ）：
```bash
cd OjisanApp
xcodegen generate
xcodebuild -project Ojisan.xcodeproj -scheme Ojisan -configuration Release -sdk iphoneos -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

## HTMLとの差分（正直版）

- 同じ：プリセット6種・スライダー3種・トグル8種・絵文字32種・語尾ルール・挨拶/褒め/近況/お誘い/締め・メンヘラ/昭和追伸・3案生成・スコア・LINEプレビュー・履歴復元・Gemini高精度・例文10種
- 良くなる：5タブで片手操作／iOS共有シート・読み上げネイティブ化／履歴無制限＋検索＋お気に入り／ダークモード／オフライン完全動作／動きが軽い
- ない：Discord直開き（共有シートに統合）・Ctrl+Enter（iOSキーボード閉じるボタンで代替）・WebのBETAバッジ装飾（ネイティブ準拠）
