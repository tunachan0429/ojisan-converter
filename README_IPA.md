# オジサン翻訳機 — iOSアプリ (IPA) 化手順

`www/index.html` を Capacitor でラップしてあります。
WindowsではIPAを直接作れない (Xcode必須) ので、GitHub Actions (無料のMac) でIPAを作ります。
できあがるのは **unsigned IPA** → Sideloadly / AltStore で無料Apple ID署名 (7日間) して入れます。

## 1. GitHubにpush

```powershell
git init
git add .
git commit -m "ojisan ios ipa"
git branch -M main
git remote add origin https://github.com/<あなた>/ojisan-converter.git
git push -u origin main
```

## 2. IPAをダウンロード

1. GitHubのリポジトリ → `Actions` タブ → `Build iOS IPA` → 最新の実行
2. `Artifacts` の `OjisanConverter-unsigned-ipa` をダウンロード
3. 中に `OjisanConverter-unsigned.ipa` が入ってます (署名なし)

## 3. iPhoneに入れる (7日署名・無料Apple ID)

### A. Sideloadly (Windowsで一番簡単・おすすめ)
1. https://sideloadly.io からSideloadlyをインストール
2. iPhoneをUSB接続、「信頼」をタップ
3. Sideloadlyに `OjisanConverter-unsigned.ipa` をドラッグ
4. Apple ID (無料でOK・使い捨て推奨) とパスワードを入力 → Start
5. iPhoneの `設定 → 一般 → VPNとデバイス管理` で自分のApple IDを「信頼」
6. アプリ起動。7日で期限切れ → 同じ操作で入れ直し

### B. AltStore (Wi-Fi自動更新あり)
1. PCにAltServer、iPhoneにAltStoreを入れる (https://altstore.io)
2. AltStoreで `OjisanConverter-unsigned.ipa` を開いてインストール
3. 同じWi-Fi内なら7日以内に自動リサイン (たまに失敗するので手動更新も必要)

## 注意 (7日署名の制限)
- 無料Apple ID: 有効期限7日、3アプリまで、10個のBundle ID/週まで
- Bundle IDは `com.ojisan.converter`。被ったら `capacitor.config.json` のappIdを変えて再ビルド
- 有料Developer ($99/年) なら1年署名・制限なし
- このアプリは完全オフライン動作なので署名切れてもデータは消えません。再インストールで復活

## 開発用コマンド
```powershell
npm install
npx cap sync ios   # www/ → ios/ にコピー
```
