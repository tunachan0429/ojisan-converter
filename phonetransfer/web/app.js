// PhoneTransfer 共有Web UI v0.1（Vanilla・Tauri/Capacitor/Safari共通）
const $ = id => document.getElementById(id);
const log = m => { const el = $('log'); el.textContent += new Date().toLocaleTimeString() + ' ' + m + '\n'; el.scrollTop = el.scrollHeight; };
const sleep = ms => new Promise(r => setTimeout(r, ms));
const CHUNK = 8 * 1024 * 1024;
const FILE_PARALLEL = 3;

let BASE = '', TOKEN = '', SESSION = '', FP_PINNED = '';

// ネイティブアプリ(Capacitor)判定: プラグインがあれば原本・裏転送経路を使う
const CAPW = window.Capacitor;
const NATIVE = !!(CAPW && CAPW.isNativePlatform && CAPW.isNativePlatform());
const PTP = (NATIVE && CAPW.Plugins) ? CAPW.Plugins.PhotosOriginal : null;
if (NATIVE) log('ネイティブ動作: 原本転送モード');

// ネイティブ用API(ピンニング済みセッション経由。WebViewのfetchは自己署名を拒否するため)
async function napi(path, opts = {}) {
  const headers = { ...(TOKEN ? { Authorization: 'Bearer ' + TOKEN } : {}), ...(opts.headers || {}) };
  const r = await PTP.apiRequest({
    method: opts.method || 'GET', url: BASE + path, headers,
    bodyText: typeof opts.body === 'string' ? opts.body : undefined,
    pinnedFp: FP_PINNED || '',
  });
  if (r.status < 200 || r.status >= 300) throw new Error(`${path} ${r.status} ${(r.body || '').slice(0, 200)}`);
  return r;
}

// QR文字列 (?v=1&fp=...#t=...) から自動入力
function parseQrString(s) {
  try {
    const u = new URL(s.trim());
    BASE = u.origin;
    $('serverUrl').value = BASE;
    const fp = u.searchParams.get('fp') || '';
    if (fp) { $('fpExpect').value = fp; FP_PINNED = fp.toLowerCase(); }
    log('QR読取: ' + BASE + ' fp=' + (fp || '').slice(0, 16) + '…');
  } catch (e) { log('QR解析失敗: URLを直接貼ってください'); }
}
$('btnFillQr').onclick = () => {
  const s = prompt('サーバー画面のQR下のURLを貼り付け');
  if (s) parseQrString(s);
};
// ページ起動時にクエリからも復元
(() => {
  try {
    if (location.search.includes('fp=')) parseQrString(location.href);
    else if (location.origin.startsWith('https://')) { BASE = location.origin; $('serverUrl').value = BASE; }
  } catch {}
})();

async function api(path, opts = {}) {
  if (NATIVE && PTP) {
    const r = await napi(path, opts);
    try { return JSON.parse(r.body); } catch { return r; }
  }
  opts.headers = { ...(TOKEN ? { Authorization: 'Bearer ' + TOKEN } : {}), ...(opts.headers || {}) };
  const res = await fetch(BASE + path, opts);
  if (!res.ok) {
    const t = await res.text().catch(() => '');
    throw new Error(`${path} ${res.status} ${t.slice(0, 200)}`);
  }
  const ct = res.headers.get('content-type') || '';
  return ct.includes('json') ? res.json() : res;
}

$('btnPair').onclick = async () => {
  BASE = $('serverUrl').value.trim().replace(/\/$/, '');
  if (!BASE) return alert('サーバーURLを入力');
  // 1) 指紋照合（announceではなくhandshake…の簡易版: /api/infoのfpとQRのfpを比較）
  // 注意: ブラウザはTLS証明書の中身をJSから読めないため、完全なピンニングはネイティブ版で行う。
  // ここではサーバー申告fpとQR fpの一致＋目視確認を必須化する。
  const info = await api('/api/info').catch(e => { log('接続失敗: ' + e.message + '（自己署名警告の許可が必要）'); throw e; });
  $('srvInfo').textContent = `接続先 ${BASE} / protocol=${info.protocol} / fp=${info.fp.slice(0, 16)}…`;
  const expect = ($('fpExpect').value || '').toLowerCase().replace(/[^0-9a-f]/g, '');
  if (expect && info.fp.toLowerCase() !== expect) {
    log('指紋不一致！接続を中止しました。QRを取り直してください。');
    alert('指紋が一致しません（なりすまし防止のため中止）');
    return;
  }
  if (!expect) {
    if (!confirm(`指紋の先頭8桁を確認してください:\n${info.fp.slice(0, 8)}\nサーバー画面と一致しますか？`)) return;
    FP_PINNED = info.fp.toLowerCase();
  } else FP_PINNED = expect;

  const pin = $('pin').value.trim();
  const dev = $('devName').value.trim() || 'iphone';
  const r = await api('/api/pair', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pin, deviceName: dev }),
  }).catch(e => {
    const m = String(e.message);
    if (m.includes('410')) log('ペアリング失敗: PINの期限切れです。PC画面で再発行してください');
    else if (m.includes('429')) log('ペアリング失敗: 試行回数オーバーのため一時ロック中。1分待って再試行');
    else if (m.includes('401')) log('ペアリング失敗: PINが違います。PC画面の6桁を入力');
    else log('ペアリング失敗: ' + e.message);
    throw e;
  });
  TOKEN = r.token; SESSION = r.sessionId;
  log(`ペア成功 session=${SESSION} (JWT 15分)`);
  $('btnSend').disabled = false;
  toast('接続OK。ファイルを送れます');
};
function toast(m) { log(m); }

function authHeaders(extra = {}) {
  return { Authorization: 'Bearer ' + TOKEN, ...extra };
}
async function sha256Hex(file, onp) {
  // 大容量対策: 500MB超はスキップ（サーバー側サイズ検証＋ネイティブで streaming hash）
  if (file.size > 500 * 1024 * 1024) return '';
  const buf = await file.arrayBuffer();
  if (onp) onp(1, 1);
  const d = await crypto.subtle.digest('SHA-256', buf);
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}

let picked = [];
$('filePick').onchange = e => {
  picked = [...e.target.files].map(f => ({ name: f.name, size: f.size, mtime: Math.floor((f.lastModified || Date.now()) / 1000), _f: f }));
  renderUp(picked.map(f => ({ name: f.name, size: f.size, status: '待機' })));
  log(`${picked.length}件選択`);
};
// ネイティブ: 端末ピッカー(原本)ボタンに入れ替え
if (NATIVE && PTP) {
  $('filePick').style.display = 'none';
  const pb = document.createElement('button');
  pb.className = 'btn btn-ghost btn-block';
  pb.textContent = '端末の写真・動画から選ぶ（原本のまま）';
  pb.onclick = async () => {
    try {
      const r = await PTP.pickAssets({ limit: 500, videos: true });
      const assets = r.assets || [];
      if (!assets.length) { log('選択なし'); return; }
      const g = await PTP.getOriginals({ ids: assets.map(a => a.id) });
      picked = (g.files || []).map(fl => ({
        name: fl.filename, size: fl.size,
        mtime: Math.floor(fl.mtime || Date.now() / 1000),
        liveGroupId: fl.liveGroupId || '', liveRole: fl.liveRole || '',
        _np: fl.path,
      }));
      renderUp(picked.map(f => ({ name: f.name, size: f.size, status: '待機（原本）' })));
      log(`${picked.length}件選択（原本）`);
    } catch (e) { log('選択失敗: ' + String(e.message || e).slice(0, 150)); }
  };
  $('filePick').after(pb);
}
function renderUp(rows) {
  $('upList').innerHTML = rows.map(r =>
    `<div class="item"><b>${escapeHtml(r.name)}</b> <small>${(r.size / 1048576).toFixed(1)}MB</small><br>
     <small class="${r.status === '完了' ? 'ok' : r.status.startsWith('失敗') ? 'err' : ''}">${escapeHtml(r.status)}</small>
     <div class="prog"><i style="width:${r.pct || 0}%"></i></div></div>`).join('');
}
function escapeHtml(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

async function headOffset(fileId) {
  if (NATIVE && PTP) {
    const r = await napi(`/api/upload?sessionId=${SESSION}&fileId=${fileId}`, { method: 'HEAD' });
    return Number(r.headers['upload-offset'] || 0);
  }
  const h = await fetch(`${BASE}/api/upload?sessionId=${SESSION}&fileId=${fileId}`, { method: 'HEAD', headers: authHeaders() });
  return Number(h.headers.get('Upload-Offset') || 0);
}

async function uploadOne(row, meta, update) {
  const f = row._f; // ブラウザFile。ネイティブは row._np (端末内パス) + row.size
  const total = row.size;
  let offset = 0;
  try { offset = await headOffset(meta.fileId); } catch {}
  const delays = [0, 1000, 3000, 5000, 10000, 20000];
  const upUrl = `${BASE}/api/upload?sessionId=${SESSION}&fileId=${meta.fileId}`;
  for (let off = offset; off < total;) {
    const end = Math.min(off + CHUNK, total);
    let ok = false, lastErr = '';
    for (let attempt = 0; attempt < delays.length; attempt++) {
      if (attempt) await sleep(delays[attempt] + Math.random() * 500);
      try {
        if (NATIVE && PTP && row._np) {
          const r = await PTP.uploadChunk({
            filePath: row._np, url: upUrl, offset: off, length: CHUNK,
            jwt: TOKEN, fileToken: meta.token, pinnedFp: FP_PINNED || '',
          });
          if (r.status === 204) { off = Number(r.uploadOffset || end); ok = true; break; }
          if (r.status === 409) { off = await headOffset(meta.fileId); ok = true; break; }
          lastErr = `chunk ${r.status}`;
          if (r.status === 401 || r.status === 403 || r.status === 422) break;
        } else {
          const blob = f.slice(off, end);
          const res = await fetch(upUrl, {
            method: 'PATCH',
            headers: { ...authHeaders(), 'X-File-Token': meta.token, 'Upload-Offset': String(off), 'Content-Type': 'application/offset+octet-stream' },
            body: blob,
          });
          if (res.status === 204) {
            off = Number(res.headers.get('Upload-Offset') || end);
            ok = true; break;
          }
          if (res.status === 409) {
            const j = await res.json().catch(() => ({}));
            off = Number(j.serverOffset || 0); ok = true; break; // 照合して継続
          }
          lastErr = `${res.status} ${(await res.text()).slice(0, 120)}`;
          if (res.status >= 400 && res.status < 500 && res.status !== 409 && res.status !== 429) break;
        }
      } catch (e) {
        lastErr = String(e.message || e).slice(0, 120);
        if (/401|403|422|pin-mismatch/.test(lastErr)) break;
      }
    }
    if (!ok) throw new Error('chunk失敗: ' + lastErr);
    row.pct = Math.round((off / total) * 100);
    row.status = `送信中 ${row.pct}%`;
    update();
  }
  // complete
  const sha = row._sha || '';
  const done = await api('/api/complete', {
    method: 'POST', headers: { 'Content-Type': 'application/json', ...authHeaders() },
    body: JSON.stringify({ sessionId: SESSION, fileId: meta.fileId, sha256: sha }),
  });
  row.status = '完了'; row.pct = 100; update();
  return done;
}

$('btnSend').onclick = async () => {
  if (!picked.length) return alert('ファイルを選択');
  const rows = picked.map(f => ({ name: f.name, size: f.size, status: '準備中', pct: 0, _f: f._f, _np: f._np, _mtime: f.mtime, _lg: f.liveGroupId, _lr: f.liveRole, _sha: '' }));
  renderUp(rows);
  const update = () => renderUp(rows);
  // ハッシュ（ブラウザの小ファイルのみ。ネイティブはスキップ＝常に転送）
  for (let i = 0; i < rows.length; i++) {
    if (!rows[i]._f) { rows[i].status = '待機'; continue; }
    rows[i].status = 'ハッシュ計算中…'; update();
    try { rows[i]._sha = await sha256Hex(rows[i]._f); } catch { rows[i]._sha = ''; }
    rows[i].status = '待機'; update();
  }
  const metas = [];
  for (let i = 0; i < rows.length; i += 500) {
    const batch = rows.slice(i, i + 500);
    const r = await api('/api/prepare', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...authHeaders() },
      body: JSON.stringify({
        sessionId: SESSION, deviceName: $('devName').value.trim() || 'iphone',
        files: batch.map((row, k) => ({
          clientId: String(i + k), fileName: row.name, size: row.size,
          mtime: row._mtime || Math.floor(Date.now() / 1000),
          kind: row.name.match(/\.(heic|jpg|jpeg|png|mov|mp4)$/i) ? 'photo' : 'file',
          liveGroupId: row._lg || undefined, liveRole: row._lr || undefined,
          sha256: row._sha || undefined,
        })),
      }),
    });
    metas.push(...r.files);
    if (r.sessionId) SESSION = r.sessionId;
  }
  // ファイル並列3
  let cursor = 0;
  async function worker() {
    while (cursor < rows.length) {
      const idx = cursor++;
      const m = metas.find(x => x.clientId === String(idx));
      if (!m || m.status === 'duplicate') { rows[idx].status = 'スキップ（重複）'; update(); continue; }
      try { await uploadOne(rows[idx], m, update); }
      catch (e) { rows[idx].status = '失敗: ' + String(e.message).slice(0, 100); update(); }
    }
  }
  await Promise.all(Array.from({ length: Math.min(FILE_PARALLEL, rows.length) }, worker));
  log('送信キュー完了');
};

$('btnList').onclick = async () => {
  const r = await api('/api/list?page=1&perPage=100').catch(e => { log('一覧失敗: ' + e.message); throw e; });
  if (NATIVE && PTP) {
    window._dlFiles = r.files;
    $('downList').innerHTML = r.files.length
      ? r.files.map((f, i) => `<div class="item"><b>${escapeHtml(f.fileName)}</b> <small>${(f.size / 1048576).toFixed(1)}MB</small><br><button class="btn btn-ghost btn-small" data-dl="${i}">保存する</button></div>`).join('')
      : '<p class="hint">まだ何もありません。</p>';
    $('downList').querySelectorAll('[data-dl]').forEach(b => b.onclick = () => nativeDownload(window._dlFiles[Number(b.dataset.dl)]));
  } else {
    $('downList').innerHTML = r.files.length
      ? r.files.map(f => `<div class="item"><b>${escapeHtml(f.fileName)}</b> <small>${(f.size / 1048576).toFixed(1)}MB</small><br><a href="${BASE}/api/download/${f.id}?token=${encodeURIComponent(TOKEN)}" download="${escapeHtml(f.fileName)}">ダウンロード</a></div>`).join('')
      : '<p class="hint">まだ何もありません。Windowsの data/library に置いたファイルが出ます。</p>';
  }
  log(`一覧 ${r.total}件`);
};

async function nativeDownload(f) {
  try {
    log(`受信中: ${f.fileName}`);
    const d = await PTP.downloadFile({
      url: `${BASE}/api/download/${f.id}?token=${encodeURIComponent(TOKEN)}`,
      jwt: TOKEN, filename: f.fileName, pinnedFp: FP_PINNED || '',
    });
    const photo = /\.(heic|heif|jpg|jpeg|png|gif|mov|mp4|m4v)$/i.test(f.fileName);
    if (photo) {
      await PTP.saveToPhotos({ path: d.path });
      log(`写真に保存: ${f.fileName}`);
    } else {
      const s = await PTP.shareFile({ path: d.path });
      log(`共有シート表示: ${f.fileName} (completed=${s.completed})`);
    }
  } catch (e) { log('保存失敗: ' + String(e.message || e).slice(0, 150)); }
}

// 同一PCのウィンドウでは自サーバーから接続情報を自動入力（iPhoneのブラウザでは無視）
(async () => {
  try {
    const h = location.hostname;
    if (h !== '127.0.0.1' && h !== 'localhost' && h !== '::1') return;
    const r = await fetch('/api/local-info');
    if (!r.ok) return;
    const info = await r.json();
    if (info.url) parseQrString(info.url);
    // ウィンドウ自身の通信は軽いloopbackに固定（QRはLAN用URLのまま表示）
    BASE = location.origin;
    $('serverUrl').value = BASE;
    if (info.pin) $('pin').value = info.pin;
    if (info.qr_svg) {
      const d = document.createElement('div');
      d.innerHTML = info.qr_svg;
      const svg = d.querySelector('svg');
      if (svg) {
        svg.style.width = '200px'; svg.style.height = '200px';
        svg.style.background = '#fff'; svg.style.borderRadius = '8px';
        $('srvInfo').prepend(svg);
      }
    }
    log('PC連携: QR・PINを自動表示しました');
    // PIN再発行ボタン（PC画面のみ）
    const rb = document.createElement('button');
    rb.className = 'btn-g btn-block';
    rb.style.marginTop = '8px';
    rb.textContent = 'PINを再発行する（期限切れ時）';
    rb.onclick = async () => {
      try {
        const rr = await fetch('/api/regen-pin', { method: 'POST' });
        const jj = await rr.json();
        if (jj.pin) { $('pin').value = jj.pin; log('PIN再発行: ' + jj.pin + '（30分有効）'); }
        else log('再発行失敗: ' + JSON.stringify(jj).slice(0, 100));
      } catch (e) { log('再発行失敗: ' + e.message); }
    };
    $('srvInfo').appendChild(rb);
  } catch (e) { /* ブラウザでは無視 */ }
})();
