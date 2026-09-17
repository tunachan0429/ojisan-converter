// 指定ポートが開くまで待つ（exe起動待ち用）
import net from 'node:net';
const port = Number(process.argv[2] || 18446);
const limit = Number(process.argv[3] || 90) * 1000;
const t0 = Date.now();
while (Date.now() - t0 < limit) {
  const ok = await new Promise(r => {
    const s = net.connect(port, '127.0.0.1');
    s.on('connect', () => { s.end(); r(true); });
    s.on('error', () => r(false));
  });
  if (ok) { console.log('PORT-OPEN'); process.exit(0); }
  await new Promise(r => setTimeout(r, 1000));
}
console.error('PORT-TIMEOUT');
process.exit(1);
