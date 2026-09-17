// 統合検証: サーバーを子プロセス起動→/api/info→pair失敗/成功→prepare→PATCH→completeまで自動試験
import { spawn } from 'node:child_process';
import https from 'node:https';
import fs from 'node:fs';

import path from 'node:path';
const PORT = 18443;
const child = spawn(process.execPath, [path.join(process.cwd(), 'server.mjs')], {
  env: { ...process.env, PT_PORT: String(PORT) },
});
let out = '';
child.stdout.on('data', d => { out += d; process.stdout.write(d); });
child.stderr.on('data', d => process.stdout.write(d));

function req(path, { method = 'GET', headers = {}, body = null } = {}) {
  return new Promise((resolve, reject) => {
    const r = https.request(
      { hostname: '127.0.0.1', port: PORT, path, method, headers, rejectUnauthorized: false },
      res => {
        const chunks = [];
        res.on('data', c => chunks.push(c));
        res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
      }
    );
    r.on('error', reject);
    if (body) r.write(body);
    r.end();
  });
}
const sleep = ms => new Promise(r => setTimeout(r, ms));

let pin = '';
for (let i = 0; i < 50; i++) {
  await sleep(300);
  const m = out.match(/PIN\(5分有効\):\s*(\d{6})/);
  if (m) { pin = m[1]; break; }
}
if (!pin) { console.error('PIN取得失敗'); child.kill(); process.exit(1); }

const info = await req('/api/info');
console.log('INFO:', info.status, info.body.slice(0, 120));
const infoJ = JSON.parse(info.body);

const bad = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin: '000000', deviceName: 'test' }) });
console.log('PAIR bad-pin:', bad.status, bad.body.slice(0, 80));

const good = await req('/api/pair', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ pin, deviceName: 'test-pc' }) });
console.log('PAIR ok:', good.status);
const { token, sessionId } = JSON.parse(good.body);
const H = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };

const payload = Buffer.from('hello-phonetransfer-' + Date.now());
const sha = (await import('node:crypto')).createHash('sha256').update(payload).digest('hex');
const prep = await req('/api/prepare', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, deviceName: 'test-pc', files: [{ clientId: 'c0', fileName: 'hello.txt', size: payload.length, mtime: 1726300000, kind: 'file', sha256: sha }] }) });
console.log('PREPARE:', prep.status, prep.body.slice(0, 160));
const { files } = JSON.parse(prep.body);
const meta = files[0];

const head1 = await req(`/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`, { method: 'HEAD', headers: { Authorization: 'Bearer ' + token } });
console.log('HEAD offset:', head1.headers['upload-offset']);

const patch = await new Promise((resolve, reject) => {
  const r = https.request({ hostname: '127.0.0.1', port: PORT, path: `/api/upload?sessionId=${sessionId}&fileId=${meta.fileId}`, method: 'PATCH', headers: { Authorization: 'Bearer ' + token, 'X-File-Token': meta.token, 'Upload-Offset': '0', 'Content-Type': 'application/offset+octet-stream', 'Content-Length': payload.length }, rejectUnauthorized: false }, res => {
    const c = []; res.on('data', x => c.push(x)); res.on('end', () => resolve({ status: res.statusCode, off: res.headers['upload-offset'] }));
  });
  r.on('error', reject); r.write(payload); r.end();
});
console.log('PATCH:', patch.status, 'newOffset=', patch.off);

const comp = await req('/api/complete', { method: 'POST', headers: H, body: JSON.stringify({ sessionId, fileId: meta.fileId, sha256: sha }) });
console.log('COMPLETE:', comp.status, comp.body.slice(0, 160));

const list = await req('/api/list?page=1&perPage=10', { headers: { Authorization: 'Bearer ' + token } });
console.log('LIST:', list.status, list.body.slice(0, 160));

const fpOk = infoJ.fp && infoJ.fp.length === 64;
console.log(fpOk && comp.status === 200 ? 'INTEG ALL OK' : 'INTEG NG');
child.kill();
process.exit(fpOk && comp.status === 200 ? 0 : 1);
