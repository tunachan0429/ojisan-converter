// Rust exe互換検証: PORT/PIN指定で全APIフローを試験
import https from 'node:https';
import crypto from 'node:crypto';

const PORT = Number(process.argv[2] || 18446);
const PIN = process.argv[3] || '135790';
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
const fail = m => { console.error('NG:', m); process.exit(1); };
const info = await req('/api/info');
if (info.status !== 200) fail('info ' + info.status);
console.log('info:', info.body.toString());
const pair = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin: PIN, deviceName: 'rust-check' }) });
if (pair.status !== 200) fail('pair ' + pair.status + ' ' + pair.body);
const { token, sessionId } = JSON.parse(pair.body.toString());
const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };
const payload = crypto.randomBytes(300000);
const sha = crypto.createHash('sha256').update(payload).digest('hex');
const prep = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'rust-check', files: [{ clientId: 'r0', fileName: 'rust.bin', size: payload.length, mtime: 1726300000, kind: 'file', sha256: sha }] }) });
if (prep.status !== 200) fail('prepare ' + prep.status);
const meta = JSON.parse(prep.body.toString()).files[0];
const base = `/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`;
// 2チャンクに分割＋HEAD再開確認
const C = 131072;
const p1 = await req(base, { method: 'PATCH', headers: { Authorization: 'Bearer ' + token, 'X-File-Token': meta.token, 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream', 'Content-Length': C }, body: payload.subarray(0, C) });
if (p1.status !== 204) fail('patch1 ' + p1.status);
const h = await req(base, { method: 'HEAD', headers: { Authorization: 'Bearer ' + token } });
if (h.headers['upload-offset'] !== String(C)) fail('head offset ' + h.headers['upload-offset']);
const rest = payload.subarray(C);
const p2 = await req(base, { method: 'PATCH', headers: { Authorization: 'Bearer ' + token, 'X-File-Token': meta.token, 'Upload-Offset': String(C), 'Content-Type': 'application/offset+octet-stream', 'Content-Length': rest.length }, body: rest });
if (p2.status !== 204) fail('patch2 ' + p2.status);
const comp = await req('/api/complete', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, fileId: meta.fileId, sha256: sha }) });
if (comp.status !== 200) fail('complete ' + comp.status + ' ' + comp.body);
console.log('stored:', comp.body.toString());
const list = await req('/api/list?page=1&perPage=100', { headers: { Authorization: 'Bearer ' + token } });
const files = JSON.parse(list.body.toString()).files;
const hit = files.find(f => f.fileName === 'rust.bin');
if (!hit) fail('list missing');
const dl = await req(`/api/download/${hit.id}?token=${encodeURIComponent(token)}`);
if (dl.status !== 200 || !dl.body.equals(payload)) fail('download mismatch');
const rg = await req(`/api/download/${hit.id}?token=${encodeURIComponent(token)}`, { headers: { Range: 'bytes=10-99', 'If-Range': dl.headers.etag } });
if (rg.status !== 206 || !rg.body.equals(payload.subarray(10, 100))) fail('range mismatch');
const qr = await req('/qr.svg');
if (qr.status !== 200 || !qr.body.toString().includes('<svg')) fail('qr.svg');
const idx = await req('/');
if (idx.status !== 200 || !idx.body.toString().includes('PhoneTransfer')) fail('index');
console.log('RUST EXE ALL OK');
