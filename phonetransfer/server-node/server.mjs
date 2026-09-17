// PhoneTransfer 参照サーバー v0.1 (Node標準 + selfsigned + qrcode-terminalのみ)
// 仕様: ../API_SPEC.md に準拠。Windows exe化前の動作検証用。
import https from 'node:https';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import selfsigned from 'selfsigned';
import qrcode from 'qrcode-terminal';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const DATA = path.join(__dirname, 'data');
const INCOMING = path.join(DATA, 'incoming');
// Local overrides from data/local.json (takes precedence over env)
let LOCAL = {};
try { const _lp = path.join(DATA, 'local.json'); if (fs.existsSync(_lp)) LOCAL = JSON.parse(fs.readFileSync(_lp, 'utf8')); } catch {}
const LIBRARY = LOCAL.PT_LIBRARY || process.env.PT_LIBRARY || path.join(DATA, 'library');
const WEBDIR = path.join(ROOT, 'web');
const PORT = Number(process.env.PT_PORT || 8443);

for (const d of [DATA, INCOMING, LIBRARY]) fs.mkdirSync(d, { recursive: true });

// ---------- 証明書 (初回生成・永続化) ----------
function loadOrCreateCert() {
  const certPath = path.join(DATA, 'cert.pem');
  const keyPath = path.join(DATA, 'key.pem');
  if (fs.existsSync(certPath) && fs.existsSync(keyPath)) {
    return { cert: fs.readFileSync(certPath, 'utf8'), key: fs.readFileSync(keyPath, 'utf8') };
  }
  const attrs = [{ name: 'commonName', value: 'PhoneTransfer-LAN' }];
  const pems = selfsigned.generate(attrs, { days: 825, keySize: 2048, algorithm: 'sha256' });
  fs.writeFileSync(certPath, pems.cert);
  fs.writeFileSync(keyPath, pems.private);
  console.log('[cert] 自己署名証明書を新規生成しました（初回のみ）');
  return { cert: pems.cert, key: pems.private };
}
const { cert, key } = loadOrCreateCert();
function certFingerprint(certPem) {
  const b64 = certPem.replace(/-----(BEGIN|END) CERTIFICATE-----/g, '').replace(/\s+/g, '');
  const der = Buffer.from(b64, 'base64');
  return crypto.createHash('sha256').update(der).digest('hex');
}
const FP = certFingerprint(cert);

// ---------- JWT秘密 ----------
function loadSecret() {
  const p = path.join(DATA, 'jwt-secret');
  if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8').trim();
  const s = crypto.randomBytes(32).toString('hex');
  fs.writeFileSync(p, s);
  return s;
}
const SECRET = loadSecret();
function b64url(buf) { return Buffer.from(buf).toString('base64url'); }
function signToken(payload) {
  const h = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const b = b64url(JSON.stringify(payload));
  const sig = crypto.createHmac('sha256', SECRET).update(h + '.' + b).digest('base64url');
  return `${h}.${b}.${sig}`;
}
function verifyToken(token) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const [h, b, sig] = parts;
  const expect = crypto.createHmac('sha256', SECRET).update(h + '.' + b).digest('base64url');
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expect))) return null;
  try {
    const p = JSON.parse(Buffer.from(b, 'base64url').toString('utf8'));
    if (p.iss !== 'phonetransfer' || p.aud !== 'lan') return null;
    if (Date.now() / 1000 > p.exp) return null;
    if (p.fp !== FP) return null; // 証明書ローテ時の失効
    return p;
  } catch { return null; }
}

// ---------- ペアリング状態 ----------
let PIN = LOCAL.PT_PIN || process.env.PT_PIN || String(crypto.randomInt(0, 1000000)).padStart(6, '0');
let pinExpires = (LOCAL.PT_PIN ? Date.now() + 24 * 3600 * 1000 : Date.now() + 5 * 60 * 1000); // 固定PINのテスト期間は24h有効
let failCount = 0;
let lockUntil = 0;
const onetime = crypto.randomBytes(12).toString('hex');
const usedOnetime = new Set();

// ---------- 台帳 (本番はSQLite、参照はJSON) ----------
const manifestPath = path.join(DATA, 'manifest.json');
let manifest = { bySha: {}, files: [] };
try { if (fs.existsSync(manifestPath)) manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8')); } catch {}
function saveManifest() { fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2)); }
const sessions = new Map(); // sessionId -> { created, device, files: Map(fileId -> meta) }

function lanIP() {
  const nets = os.networkInterfaces();
  for (const arr of Object.values(nets)) for (const n of arr || []) {
    if (n.family === 'IPv4' && !n.internal && !n.address.startsWith('169.254.')) return n.address;
  }
  return '127.0.0.1';
}

// ---------- HTTPユーティリティ ----------
function sendJson(res, code, obj, extra = {}) {
  const body = Buffer.from(JSON.stringify(obj));
  res.writeHead(code, { 'Content-Type': 'application/json', 'Content-Length': body.length, ...extra });
  res.end(body);
}
function readJson(req, limit = 2 * 1024 * 1024) {
  return new Promise((resolve, reject) => {
    const chunks = []; let len = 0;
    req.on('data', c => { len += c.length; if (len > limit) { reject(new Error('too-large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => { try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : {}); } catch (e) { reject(e); } });
    req.on('error', reject);
  });
}
function bearer(req) {
  const h = req.headers.authorization || '';
  const m = h.match(/^Bearer\s+(.+)$/);
  return m ? verifyToken(m[1]) : null;
}
const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
function serveStatic(req, res, pathname) {
  let rel = decodeURIComponent(pathname === '/' ? '/index.html' : pathname).replace(/^\/+/, '');
  if (rel.includes('..')) { res.writeHead(400); res.end('bad path'); return true; }
  const fp = path.join(WEBDIR, rel);
  if (fs.existsSync(fp) && fs.statSync(fp).isFile()) {
    const ext = path.extname(fp).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    fs.createReadStream(fp).pipe(res);
    return true;
  }
  return false;
}
function walkFiles(dir, base = '') {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, e.name);
    const rel = base ? base + '/' + e.name : e.name;
    if (e.isDirectory()) out.push(...walkFiles(full, rel));
    else if (e.isFile()) {
      const st = fs.statSync(full);
      out.push({ id: Buffer.from(rel).toString('base64url'), fileName: e.name, rel, size: st.size, mtime: Math.floor(st.mtimeMs / 1000) });
    }
  }
  return out;
}

// ---------- サーバー ----------
const server = https.createServer({ cert, key }, async (req, res) => {
  try {
    const u = new URL(req.url, 'https://x');
    const p = u.pathname;

    if (req.method === 'GET' && p === '/api/info') {
      return sendJson(res, 200, { name: 'PhoneTransfer', version: '0.2', protocol: 1, fp: FP, port: PORT, downloadTokenQuery: true });
    }

    if (req.method === 'POST' && p === '/api/pair') {
      const body = await readJson(req).catch(() => null);
      if (!body) return sendJson(res, 400, { error: 'bad-json' });
      if (Date.now() < lockUntil) return sendJson(res, 429, { error: 'locked', retryAfter: Math.ceil((lockUntil - Date.now()) / 1000) });
      if (Date.now() > pinExpires) return sendJson(res, 410, { error: 'pin-expired', hint: 'サーバー側で新しいPINを表示してください' });
      if (body.pin !== PIN) {
        failCount++;
        if (failCount >= 5) { lockUntil = Date.now() + 60000; failCount = 0; return sendJson(res, 429, { error: 'locked', retryAfter: 60 }); }
        return sendJson(res, 401, { error: 'bad-pin', remain: 5 - failCount });
      }
      failCount = 0;
      const sessionId = 's_' + crypto.randomBytes(8).toString('hex');
      sessions.set(sessionId, { created: Date.now(), device: body.deviceName || 'iphone', files: new Map() });
      const now = Math.floor(Date.now() / 1000);
      const token = signToken({ iss: 'phonetransfer', aud: 'lan', fp: FP, jti: crypto.randomBytes(8).toString('hex'), iat: now, exp: now + 900, dev: body.deviceName || '' });
      return sendJson(res, 200, { token, expiresIn: 900, sessionId, serverTime: now });
    }

    // 以降は認証必須
    const needAuth = p.startsWith('/api/prepare') || p.startsWith('/api/upload') || p.startsWith('/api/complete') || p.startsWith('/api/cancel') || p.startsWith('/api/list') || p.startsWith('/api/download');
    let claims = null;
    if (needAuth) {
      claims = bearer(req);
      // ブラウザの直接リンク（aタグ遷移）用: ?token= も許可（テスト期間の便宜措置）
      if (!claims && (p.startsWith('/api/download/'))) {
        claims = verifyToken(u.searchParams.get('token') || '');
      }
      if (!claims) return sendJson(res, 401, { error: 'unauthorized' });
    }

    if (req.method === 'POST' && p === '/api/prepare') {
      const body = await readJson(req, 5 * 1024 * 1024).catch(() => null);
      if (!body || !Array.isArray(body.files)) return sendJson(res, 400, { error: 'bad-request' });
      if (body.files.length > 500) return sendJson(res, 413, { error: 'too-many', max: 500 });
      let sess = sessions.get(body.sessionId);
      if (!sess) { sess = { created: Date.now(), device: body.deviceName || claims.dev || 'iphone', files: new Map() }; sessions.set(body.sessionId || ('s_' + crypto.randomBytes(8).toString('hex')), sess); }
      const sid = body.sessionId || [...sessions.keys()].pop();
      sess.device = body.deviceName || sess.device;
      const out = [];
      for (const f of body.files) {
        if (!f.clientId || !f.fileName || !Number.isFinite(f.size)) continue;
        if (f.sha256 && manifest.bySha[f.sha256]) { out.push({ clientId: f.clientId, fileId: '', token: '', status: 'duplicate' }); continue; }
        const fileId = 'f_' + crypto.randomBytes(8).toString('hex');
        const ftoken = crypto.randomBytes(12).toString('hex');
        sess.files.set(fileId, {
          clientId: f.clientId, fileName: path.basename(String(f.fileName)).slice(0, 180),
          size: f.size, sha256: f.sha256 || '', mtime: f.mtime || 0, kind: f.kind || 'file',
          liveGroupId: f.liveGroupId || '', liveRole: f.liveRole || '',
          offset: 0, token: ftoken, part: path.join(INCOMING, fileId + '.part'),
        });
        out.push({ clientId: f.clientId, fileId, token: ftoken, status: 'ready' });
      }
      return sendJson(res, 200, { sessionId: sid, files: out });
    }

    if (p === '/api/upload' && (req.method === 'HEAD' || req.method === 'PATCH')) {
      const sid = u.searchParams.get('sessionId'), fid = u.searchParams.get('fileId');
      const sess = sessions.get(sid);
      const meta = sess?.files.get(fid);
      if (!meta) return sendJson(res, 404, { error: 'no-such-file' });
      if (req.method === 'HEAD') {
        let off = 0;
        try { off = fs.existsSync(meta.part) ? fs.statSync(meta.part).size : 0; } catch {}
        meta.offset = off;
        return sendJson(res, 200, { offset: off }, { 'Upload-Offset': String(off), 'Upload-Length': String(meta.size) });
      }
      // PATCH
      if (req.headers['x-file-token'] !== meta.token) return sendJson(res, 403, { error: 'bad-file-token' });
      const off = Number(req.headers['upload-offset']);
      let cur = 0;
      try { cur = fs.existsSync(meta.part) ? fs.statSync(meta.part).size : 0; } catch {}
      if (!Number.isFinite(off) || off !== cur) return sendJson(res, 409, { error: 'offset-mismatch', serverOffset: cur }, { 'Upload-Offset': String(cur) });
      const ctype = req.headers['content-type'] || '';
      if (!ctype.includes('application/offset+octet-stream')) return sendJson(res, 415, { error: 'bad-content-type' });
      if (cur + Number(req.headers['content-length'] || 0) > meta.size + 1024) return sendJson(res, 413, { error: 'too-large' });
      await new Promise((resolve, reject) => {
        const ws = fs.createWriteStream(meta.part, { flags: 'a' });
        req.pipe(ws);
        req.on('end', () => ws.end(resolve));
        req.on('error', reject); ws.on('error', reject);
      });
      const now2 = fs.statSync(meta.part).size;
      meta.offset = now2;
      res.writeHead(204, { 'Upload-Offset': String(now2) });
      return res.end();
    }

    if (req.method === 'POST' && p === '/api/complete') {
      const body = await readJson(req).catch(() => null);
      const sess = sessions.get(body?.sessionId);
      const meta = sess?.files.get(body?.fileId);
      if (!meta) return sendJson(res, 404, { error: 'no-such-file' });
      if (!fs.existsSync(meta.part)) return sendJson(res, 409, { error: 'empty' });
      const hash = crypto.createHash('sha256');
      await new Promise((resolve, reject) => {
        const rs = fs.createReadStream(meta.part);
        rs.on('data', d => hash.update(d)); rs.on('end', resolve); rs.on('error', reject);
      });
      const digest = hash.digest('hex');
      if (body.sha256 && body.sha256.toLowerCase() !== digest) {
        return sendJson(res, 422, { error: 'hash-mismatch', serverSha: digest });
      }
      const d = meta.mtime ? new Date(meta.mtime * 1000) : new Date();
      const yyyy = d.getFullYear(), mm = String(d.getMonth() + 1).padStart(2, '0'), dd = String(d.getDate()).padStart(2, '0');
      const dev = String(sess.device || 'iphone').replace(/[\\/:*?"<>|]/g, '_').slice(0, 40) || 'iphone';
      const destDir = path.join(LIBRARY, `${yyyy}`, `${mm}-${dd}`, dev);
      fs.mkdirSync(destDir, { recursive: true });
      let dest = path.join(destDir, meta.fileName);
      if (fs.existsSync(dest)) {
        const ext = path.extname(dest), base = path.basename(dest, ext);
        let i = 1; while (fs.existsSync(path.join(destDir, `${base} (${i})${ext}`))) i++;
        dest = path.join(destDir, `${base} (${i})${ext}`);
      }
      fs.renameSync(meta.part, dest);
      try { if (meta.mtime) fs.utimesSync(dest, new Date(), new Date(meta.mtime * 1000)); } catch {}
      manifest.bySha[digest] = path.relative(LIBRARY, dest);
      manifest.files.push({ sha: digest, path: path.relative(LIBRARY, dest), size: meta.size, at: Date.now() });
      saveManifest();
      return sendJson(res, 200, { status: 'stored', path: path.relative(LIBRARY, dest) });
    }

    if (req.method === 'POST' && p === '/api/cancel') {
      const body = await readJson(req).catch(() => ({}));
      const sess = sessions.get(body.sessionId);
      const meta = sess?.files.get(body.fileId);
      if (body.discard && meta && fs.existsSync(meta.part)) fs.unlinkSync(meta.part);
      return sendJson(res, 200, { status: 'cancelled' });
    }

    if (req.method === 'GET' && p === '/api/list') {
      const page = Math.max(1, Number(u.searchParams.get('page') || 1));
      const per = Math.min(200, Math.max(1, Number(u.searchParams.get('perPage') || 100)));
      const all = walkFiles(LIBRARY);
      const total = all.length;
      const files = all.slice((page - 1) * per, page * per);
      return sendJson(res, 200, { total, files });
    }

    if (req.method === 'GET' && p.startsWith('/api/download/')) {
      const id = p.slice('/api/download/'.length);
      const all = walkFiles(LIBRARY);
      const hit = all.find(f => f.id === id);
      if (!hit) return sendJson(res, 404, { error: 'not-found' });
      const full = path.join(LIBRARY, hit.rel);
      const st = fs.statSync(full);
      const etag = '"' + crypto.createHash('sha256').update(hit.rel + ':' + st.size + ':' + st.mtimeMs).digest('hex').slice(0, 16) + '"';
      const range = req.headers.range;
      res.setHeader('Accept-Ranges', 'bytes');
      res.setHeader('ETag', etag);
      if (!range) {
        res.writeHead(200, { 'Content-Length': st.size, 'Content-Type': 'application/octet-stream', 'Content-Disposition': `attachment; filename="${encodeURIComponent(hit.fileName)}"` });
        return fs.createReadStream(full).pipe(res);
      }
      const m = range.match(/bytes=(\d+)-(\d*)/);
      if (!m) { res.writeHead(416, { 'Content-Range': `bytes */${st.size}` }); return res.end(); }
      let start = Number(m[1]), end = m[2] ? Number(m[2]) : st.size - 1;
      const ifRange = req.headers['if-range'];
      if (ifRange && ifRange !== etag) {
        res.writeHead(200, { 'Content-Length': st.size, 'Content-Type': 'application/octet-stream' });
        return fs.createReadStream(full).pipe(res);
      }
      if (start >= st.size) { res.writeHead(416, { 'Content-Range': `bytes */${st.size}` }); return res.end(); }
      end = Math.min(end, st.size - 1);
      res.writeHead(206, { 'Content-Range': `bytes ${start}-${end}/${st.size}`, 'Content-Length': end - start + 1, 'Content-Type': 'application/octet-stream' });
      return fs.createReadStream(full, { start, end }).pipe(res);
    }

    if (req.method === 'GET' && !p.startsWith('/api/')) {
      if (serveStatic(req, res, p)) return;
      return sendJson(res, 404, { error: 'not-found', hint: 'web/ にUIを配置してください（次のステップで作成）' });
    }
    return sendJson(res, 404, { error: 'not-found' });
  } catch (e) {
    console.error(e);
    try { return sendJson(res, 500, { error: 'internal' }); } catch {}
  }
});

server.listen(PORT, '0.0.0.0', () => {
  const ip = lanIP();
  const url = `https://${ip}:${PORT}/?v=1&fp=${FP}#t=${onetime}`;
  console.log('==============================================');
  console.log(' PhoneTransfer 参照サーバー起動');
  console.log(` 待受: https://0.0.0.0:${PORT}  (LAN IP: ${ip})`);
  console.log(` 証明書指紋(SHA256): ${FP}`);
  console.log(` PIN(5分有効): ${PIN}`);
  console.log(' QR(このURLをiPhoneで読む):');
  qrcode.generate(url, { small: true });
  console.log(url);
  console.log(' 注意: ブラウザは自己署名で警告が出ます。「詳細→進む」で許可（TOFU初回のみ）。');
  console.log(' 終了は Ctrl+C。PIN再発行は再起動。');
  console.log('==============================================');
});
