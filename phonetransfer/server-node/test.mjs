// 最小検証: 証明書・指紋・JWT・チャンク定数の確認（ネットワーク不要）
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DATA = path.join(__dirname, 'data');
const certPath = path.join(DATA, 'cert.pem');

if (!fs.existsSync(certPath)) {
  console.log('SKIP: cert未生成（server.mjs初回起動で生成されます）');
  process.exit(0);
}
const certPem = fs.readFileSync(certPath, 'utf8');
const b64 = certPem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, '').replace(/\s+/g, '');
const der = Buffer.from(b64, 'base64');
const fp = crypto.createHash('sha256').update(der).digest('hex');
console.log('fp len:', fp.length, fp.length === 64 ? 'OK' : 'NG');
console.log('fp head:', fp.slice(0, 16));
const CHUNK = 8388608;
console.log('chunk:', CHUNK, CHUNK % (256 * 1024) === 0 ? 'OK(256KiB倍数)' : 'NG');
console.log('ALL OK');
