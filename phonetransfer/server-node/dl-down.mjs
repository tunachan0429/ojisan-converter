// ダウンロード検証: ?token= 付きリンクで実バイトが取れること（レジュームRange含む）
import { spawn } from 'node:child_process';
import https from 'node:https';
import crypto from 'node:crypto';
import path from 'node:path';

const PORT = 18445;
const child = spawn(process.execPath, [path.join(process.cwd(), 'server.mjs')], {
  env: { ...process.env, PT_PORT: String(PORT) },
});
let out = '';
child.stdout.on('data', d => { out += d; });
child.stderr.on('data', d => process.stdout.write(d));
const sleep = ms => new Promise(r => setTimeout(r, ms));

function req(pathname, { method = 'GET', headers = {}, body = null } = {}) {
  return new Promise((resolve, reject) => {
    const r = https.request({ hostname: '127.0.0.1', port: PORT, path: pathname, method, headers, rejectUnauthorized: false }, res => {
      const c = []; res.on('data', x => c.push(x));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(c) }));
    });
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}
let pin = '';
for (let i = 0; i < 50; i++) { await sleep(300); const m = out.match(/PIN\(5分有効\):\s*(\d{6})/); if (m) { pin = m[1]; break; } }
const pair = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin, deviceName: 'dltest' }) });
const { token, sessionId } = JSON.parse(pair.body.toString());
const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };
const payload = crypto.randomBytes(60000);
const sha = crypto.createHash('sha256').update(payload).digest('hex');
const prep = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'dltest', files: [{ clientId: 'x', fileName: 'down.bin', size: payload.length, kind: 'file', sha256: sha }] }) });
const meta = JSON.parse(prep.body.toString()).files[0];
await req(`/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`, {
  method: 'PATCH',
  headers: { Authorization: 'Bearer ' + token, 'X-File-Token': meta.token, 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream', 'Content-Length': payload.length },
  body: payload,
});
await req('/api/complete', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, fileId: meta.fileId, sha256: sha }) });

// 1) Authorizationヘッダなし＋?token=なし → 401
const noauth = await req('/api/download/' + 'xxx');
console.log('noauth status (want 401/404):', noauth.status);
// 2) 正規: listでid取得→?token=で全取得
const list = await req('/api/list?page=1&perPage=100', { headers: { Authorization: 'Bearer ' + token } });
const files = JSON.parse(list.body.toString()).files;
const hit = files.find(f => f.fileName === 'down.bin');
const full = await req(`/api/download/${hit.id}?token=${encodeURIComponent(token)}`);
console.log('token-download:', full.status, 'bytes=', full.body.length);
// 3) Range再開
const part = await req(`/api/download/${hit.id}?token=${encodeURIComponent(token)}`, { headers: { Range: 'bytes=1000-', 'If-Range': full.headers.etag } });
console.log('range-download:', part.status, part.headers['content-range'], 'bytes=', part.body.length);
const ok = full.status === 200 && full.body.equals(payload)
  && part.status === 206 && part.body.equals(payload.subarray(1000));
console.log(ok ? 'DOWNLOAD ALL OK' : 'DOWNLOAD NG');
child.kill();
process.exit(ok ? 0 : 1);
