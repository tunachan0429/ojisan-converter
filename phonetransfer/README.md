# PhoneTransfer v0.1（参照実装）

Windowsがお店、iPhoneがお客さん。同一Wi-FiでHTTPS直送します。

## 動かし方（Windows）

1. `phonetransfer/server-node` で `npm install`
2. `npm start`（初回は自己署名証明書を自動生成）
3. 表示される QR・PIN・指紋を確認
4. iPhoneのSafariでQR下のURLを開く→ `../web/index.html` が配られる
   - 自己署名の警告は「詳細→進む」（初回のみ、指紋一致を確認）
   - PIN入力→ファイル選択→送信

## 検証済み

- `node integ.mjs` — pair→prepare→PATCH→complete→list の一連（小ファイル）
- `node resume-test.mjs` — 20MBを8MiB分割→中断→HEAD再開→409検証→重複スキップ

## 仕様

- `API_SPEC.md` が正本。チャンク既定 8MiB、ファイル並列3、各ファイル内逐次。
- 保存先（参照）: `server-node/data/library/YYYY/MM-DD/デバイス名/`
- 本番は `~/Pictures/PhoneTransfer`＋SQLite＋Tauri単一exeに移行予定。

## 次の作業

1. 実機（iPhone Safari）での小ファイル送受信確認
2. `ios-plugin/PhotosOriginalPlugin.swift` を app-shell に組込み→CIで署名なしIPA
3. Rust導入後に Tauri v2＋Axum 本番サーバーへ移植（APIはそのまま）
