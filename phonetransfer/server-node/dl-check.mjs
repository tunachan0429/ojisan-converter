// 保存先確認: localhost経由で1件送り、stored pathがDownloads配下か検証
import https from 'node:https';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const PORT = 8443;
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
const pair = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin: '246810', deviceName: 'dl-check' }) });
if (pair.status !== 200) { console.error('PAIR NG:', pair.status, pair.body); process.exit(1); }
const { token, sessionId } = JSON.parse(pair.body);
const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };
const payload = Buffer.from('downloads-check-' + Date.now());
const sha = crypto.createHash('sha256').update(payload).digest('hex');
const prep = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'dl-check', files: [{ clientId: 'd0', fileName: 'dl-check.txt', size: payload.length, mtime: Math.floor(Date.now() / 1000), kind: 'file', sha256: sha }] }) });
const meta = JSON.parse(prep.body).files[0];
const base = `/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`;
const patched = await new Promise((resolve, reject) => {
  const r = https.request({ hostname: '127.0.0.1', port: PORT, path: base, method: 'PATCH', headers: { Authorization: 'Bearer ' + token, 'X-File-Token': meta.token, 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream', 'Content-Length': payload.length }, rejectUnauthorized: false }, res => {
    res.on('data', () => {}); res.on('end', () => resolve(res.statusCode));
  });
  r.on('error', reject); r.write(payload); r.end();
});
const comp = await req('/api/complete', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, fileId: meta.fileId, sha256: sha }) });
console.log('PATCH:', patched, 'COMPLETE:', comp.status, comp.body);
const rel = JSON.parse(comp.body).path;
const home = process.env.USERPROFILE;
const full = path.join(home, 'Downloads', 'PhoneTransfer', rel);
console.log('stored rel:', rel);
console.log('exists in Downloads:', fs.existsSync(full) ? 'YES ' + full : 'NO -> ' + full);
process.exit(comp.status === 200 && fs.existsSync(full) ? 0 : 1);
