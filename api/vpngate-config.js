export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  const hostOrIp = (req.query.host || '').toString().trim();
  if (!hostOrIp) return res.status(400).json({ error: 'host is required' });
  try {
    // Read local CSV bundled with the project to avoid remote challenges
    const { fileURLToPath } = await import('url');
    const path = await import('path');
    const fs = await import('fs');
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);

    // Try multiple candidate locations for vpngate.csv in the Vercel bundle
    const candidates = [
      path.join(__dirname, 'vpngate.csv'),
      path.join(__dirname, '..', 'vpngate.csv'),
      path.join(process.cwd(), 'vpngate.csv'),
      path.join(process.cwd(), 'vyntra_app_aiks', 'vpngate.csv'),
    ];

    let csv = null;
    for (const p of candidates) {
      try {
        if (fs.existsSync(p)) {
          csv = fs.readFileSync(p, 'utf8');
          break;
        }
      } catch (_) { /* ignore */ }
    }

    // Fallback: fetch live CSV if local file not found
    if (!csv) {
      const bypassHeader = req.headers['x-vercel-protection-bypass'];
      const headers = {
        'User-Agent': 'Vyntra-VPN-Android/1.0',
        'Accept': 'text/plain,*/*',
        'Cache-Control': 'no-cache',
      };
      if (bypassHeader) headers['X-Vercel-Protection-Bypass'] = bypassHeader;
      const resp = await fetch('https://www.vpngate.net/api/iphone/', { headers, cache: 'no-store' });
      const text = await resp.text();
      if (!resp.ok || !text || !text.includes('HostName')) {
        return res.status(502).json({ error: 'Unable to load VPNGate CSV (local and remote failed)' });
      }
      csv = text;
    }
    const lines = csv.split(/\r?\n/).filter(l => l && !l.startsWith('#') && !l.startsWith('*'));
    const header = lines.find(l => /HostName,/i.test(l));
    if (!header) return res.status(502).json({ error: 'Invalid CSV' });
    const cols = header.split(',');
    const idx = Object.fromEntries(cols.map((c, i) => [c.trim(), i]));
    const needle = hostOrIp.toLowerCase();
    let want = null;
    for (let i = 1; i < lines.length; i++) {
      const parts = lines[i].split(',');
      if (parts.length < cols.length) continue;
      const hn = (parts[idx['HostName']] || '').trim().toLowerCase();
      const ip = (parts[idx['IP']] || '').trim();
      if (hn === needle || ip === hostOrIp.trim()) { want = parts; break; }
    }
    if (!want) return res.status(404).json({ error: 'Not found' });
    const b64 = (want[idx['OpenVPN_ConfigData_Base64']] || '').trim();
    if (!b64) return res.status(404).json({ error: 'Config missing' });
    return res.status(200).json({ host: hostOrIp, ovpnBase64: b64 });
  } catch (e) {
    return res.status(500).json({ error: 'Server error', message: String(e) });
  }
}


