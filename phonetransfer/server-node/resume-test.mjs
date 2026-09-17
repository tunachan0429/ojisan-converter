// 安定性検証: 20MBを8MiBチャンクで送り、途中で中断→HEAD再開→完成まで試験
import { spawn } from 'node:child_process';
import https from 'node:https';
import crypto from 'node:crypto';
import path from 'node:path';

const PORT = 18444;
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
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(c).toString('utf8') }));
    });
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}
function patchChunk(url, jwt, ftoken, offset, buf) {
  return new Promise((resolve, reject) => {
    const r = https.request({ hostname: '127.0.0.1', port: PORT, path: url, method: 'PATCH', headers: { Authorization: 'Bearer ' + jwt, 'X-File-Token': ftoken, 'Upload-Offset': String(offset), 'Content-Type': 'application/offset+octet-stream', 'Content-Length': buf.length }, rejectUnauthorized: false }, res => {
      const c = []; res.on('data', x => c.push(x));
      res.on('end', () => resolve({ status: res.statusCode, off: res.headers['upload-offset'], body: Buffer.concat(c).toString('utf8') }));
    });
    r.on('error', reject); r.write(buf); r.end();
  });
}

let pin = '';
for (let i = 0; i < 50; i++) { await sleep(300); const m = out.match(/PIN\(5分有効\):\s*(\d{6})/); if (m) { pin = m[1]; break; } }
if (!pin) { console.error('PIN取得失敗'); child.kill(); process.exit(1); }

const good = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin, deviceName: 'resume-test' }) });
const { token, sessionId } = JSON.parse(good.body);
const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };

// 20MB乱数（8MiB×2 + 残り）
const SIZE = 20 * 1024 * 1024;
const data = crypto.randomBytes(SIZE);
const sha = crypto.createHash('sha256').update(data).digest('hex');
console.log('test file:', SIZE, 'sha:', sha.slice(0, 16) + '…');

const prep = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'resume-test', files: [{ clientId: 'big0', fileName: 'big20.bin', size: SIZE, mtime: 1726300000, kind: 'file', sha256: sha }] }) });
const meta = JSON.parse(prep.body).files[0];
const base = `/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`;

// chunk1 (0〜8MiB) 送信→中断を模擬
const C = 8 * 1024 * 1024;
let r1 = await patchChunk(base, token, meta.token, 0, data.subarray(0, C));
console.log('chunk1:', r1.status, 'off=', r1.off);
// HEADで再開位置確認
const h = await req(base, { method: 'HEAD', headers: { Authorization: 'Bearer ' + token } });
console.log('HEAD after interrupt:', h.headers['upload-offset']);
// わざとずれたoffsetで送って409を確認
const wrong = await patchChunk(base, token, meta.token, 0, data.subarray(0, 1024));
console.log('wrong-offset expect 409:', wrong.status, wrong.body.slice(0, 80));
// 正しい位置から残りを送信
let off = Number(h.headers['upload-offset']);
for (; off < SIZE;) {
  const end = Math.min(off + C, SIZE);
  const r = await patchChunk(base, token, meta.token, off, data.subarray(off, end));
  if (r.status !== 204 && r.status !== 409) { console.error('PATCH失敗', r.status, r.body); child.kill(); process.exit(1); }
  off = Number(r.off ?? end);
  console.log(`chunk off=${off}/${SIZE}`);
}
const comp = await req('/api/complete', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, fileId: meta.fileId, sha256: sha }) });
console.log('COMPLETE:', comp.status, comp.body.slice(0, 120));
// 重複スキップ確認: 同じshaでprepare→duplicate
const prep2 = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'resume-test', files: [{ clientId: 'dup', fileName: 'big20.bin', size: SIZE, sha256: sha }] }) });
console.log('DUPLICATE check:', prep2.body.slice(0, 120));
const ok = comp.status === 200 && prep2.body.includes('duplicate');
console.log(ok ? 'RESUME ALL OK' : 'RESUME NG');
child.kill();
process.exit(ok ? 0 : 1);
