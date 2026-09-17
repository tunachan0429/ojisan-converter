# PhoneTransfer API仕様 v0.1（確定版・参照実装用）

方針: Windowsが常時サーバー、iPhoneは常にクライアント。
同一Wi-Fiのみ。HTTPS必須。LocalSend語彙（prepare/session/token）を借用するが互換はしない。
並列は「ファイル並列最大3、各ファイル内は逐次」。チャンク既定 8MiB（8,388,608B）。

## 0. 接続情報（QR）

QRペイロード（JSONをURLフラグメントに格納）:

```
https://<IP>:<PORT>/?v=1&fp=<SHA256(certDER hex)>&token=<pairing-onetime>
```

- `fp`: サーバ証明書DERのSHA-256 hex（小文字）。クライアントはTLSハンドシェイクで取得した証明書と必ず照合する（announceの値は信用しない）。
- `token`: 数分有効の使い捨てペアリング用。ログに残さない（クエリではなく初回POST bodyで使う）。
- mDNSは補助: `_phototransfer._tcp.local` TXTに `port, fp(先頭16桁), v=1`。見つからなくてもQRで直結できること。

## 1. 認証

### POST /api/pair
Request:
```json
{ "pin": "123456", "deviceName": "kotak-iPhone", "onetime": "xxx", "clientFpCheck": "ab12..." }
```
- PINは6桁、有効期限5分、5回失敗で60秒ロック＋指数待機。
- 成功: `200 { "token": "<JWT 15分>", "expiresIn": 900, "sessionId": "<24h転送台帳ID>", "serverTime": 172638... }`
- 失敗: `401 { "error": "bad-pin" }` / `429 { "error": "locked", "retryAfter": 60 }`
- JWTは `Authorization: Bearer` ヘッダでのみ送る（Cookie化しない）。ペイロードに `fp, jti, iss=phonetransfer, aud=lan` をbindする。

## 2. 上り（iPhone→Windows）

### POST /api/prepare
Headers: `Authorization: Bearer <JWT>`
Request:
```json
{
  "sessionId": "<24h>",
  "deviceName": "kotak-iPhone",
  "files": [
    { "clientId": "c1", "fileName": "IMG_1234.HEIC", "size": 3145728, "mtime": 1726380000,
      "kind": "photo", "sha256": "hex(任意・あれば高速skip用)", "liveGroupId": "lg1", "liveRole": "photo" }
  ]
}
```
Response:
```json
{
  "sessionId": "<same>",
  "files": [
    { "clientId": "c1", "fileId": "f_abc", "token": "per-file-onetime", "status": "ready" },
    { "clientId": "c2", "fileId": "f_def", "token": "", "status": "duplicate" }
  ]
}
```
- `duplicate`: サーバがsize+sha256で既存と判定。クライアントは送らずスキップ。
- `status=ready` のみ後続アップロード可。
- 数千件対応: 1回のprepareは最大500件。超えたら分割して呼ぶ。

### HEAD /api/upload?sessionId=&fileId=
Headers: `Authorization: Bearer`
Response headers: `Upload-Offset: <受信済みバイト数>`, `Upload-Length: <総サイズ>`
- 再開位置の照会用。中断後に必ず呼ぶ。

### PATCH /api/upload?sessionId=&fileId=
Headers:
```
Authorization: Bearer <JWT>
X-File-Token: <per-file token>
Upload-Offset: <number>
Content-Type: application/offset+octet-stream
```
Body: 生バイナリ（1〜8MiB、256KiB倍数推奨）
Response: `204` + `Upload-Offset: <new offset>`
Errors:
- `409 {error:offset-mismatch, serverOffset: N}` → クライアントはNから送り直す
- `422 {error:bad-sha}` はcomplete時のみ
- `401/403` 認証切れ → /api/pair再取得（sessionは維持）

### POST /api/complete
```json
{ "sessionId": "...", "fileId": "f_abc", "sha256": "hex必須" }
```
- サーバは `.part` をSHA-256検証 → 日付フォルダに`rename` → 台帳に記録。
- 成功: `200 { "status": "stored", "path": "2026/09-16/iPhone/IMG_1234.HEIC" }`
- 失敗: `422 {error:hash-mismatch}` → クライアントは該当ファイルを先頭から再送。

## 3. 下り（Windows→iPhone）

### GET /api/list?page=1&perPage=100
Response:
```json
{ "total": 2, "files": [ { "id": "w1", "fileName": "doc.zip", "size": 12345, "mtime": 1726..., "sha256": "hex", "etag": "\"abc\"" } ] }
```

### GET /api/download/:id
- `Accept-Ranges: bytes` 必須。`ETag: "<sha先頭16>"` を返す。
- レジューム: `Range: bytes=<received>-` + `If-Range: <ETag>` → `206 + Content-Range`。
- 範囲不正: `416` → クライアントは先頭から取り直す。
- 変更検出: ETag不一致で `200` 全送 → クライアントは破棄して最初から。

## 4. その他

### GET /api/info
```json
{ "name": "PhoneTransfer", "version": "0.1", "protocol": 1, "fp": "hex", "port": 8443 }
```
- 認証不要。指紋の目視照合用（先頭8桁表示）。

### POST /api/cancel
```json
{ "sessionId": "...", "fileId": "f_abc" }
```
- `.part` を保持したまま中断（再開可）。破棄したい場合は `{"discard": true}`。

## 5. 保存則（Windows）

- 一時: `<store>/.incoming/<fileId>.part` に追記。TEMPと確定先は同一FS必須。
- 確定: `Pictures/PhoneTransfer/YYYY/MM-DD/<deviceName>/<fileName>`。衝突は ` (1)` 連番。上書き禁止。
- Live: 同一 `liveGroupId` を `IMG_xxxx.HEIC + IMG_xxxx_live.MOV + IMG_xxxx_live.json` で保存。
- 台帳: SQLite本番、参照実装はJSON（`data/manifest.json`）。`sha256→path` で重複排除。`sessionId/fileId/offset/sha` を永続化。
- mtime復元: EXIF撮影日時優先、無ければクライアントmtime。

## 6. セキュリティ則

- 平文HTTPは出さない（LocalSendのブラウザ用平文fallbackは採用しない）。
- PINはクエリに載せない（body＋TLS）。JWTは短命10〜15分、sessionは12〜24hで分離。
- レート制限＋使い捨てtoken（jti denylist）。
- 指紋検証のテスト必須: QR指紋≠ハンドシェイク指紋なら接続拒否＋警告表示。

## 7. 既定値

- chunk: 8388608B、ファイル並列: 3、リトライ: [0,1s,3s,5s,10s,20s]+jitter、prepare上限500件/回、list 100件/頁。
