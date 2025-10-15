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
      path.join(__dirname, '..', 'data', 'vpngate.csv'),
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
    // Normalize content (strip BOM if present)
    const normalized = csv.replace(/^\uFEFF/, '');
    const lines = normalized
      .split(/\r?\n/)
      .filter(l => (l || '').trim() && !l.startsWith('#') && !l.startsWith('*'));
    // Find header: prefer the first line containing HostName (case-insensitive); fallback to the first non-comment line
    let header = lines.find(l => /hostname/i.test(l)) || lines[0];
    if (!header) return res.status(502).json({ error: 'Invalid CSV' });

    const cols = header.split(',').map(s => s.trim());
    const lower = cols.map(c => c.toLowerCase());
    const findColIncludes = (needles) => {
      for (let i = 0; i < lower.length; i++) {
        const cell = lower[i];
        for (const n of needles) {
          if (cell.includes(n)) return i;
        }
      }
      return -1;
    };

    const hostIdx = findColIncludes(['hostname', 'host name']);
    const ipIdx = findColIncludes(['ip']);
    const b64Idx = findColIncludes([
      'openvpn_configdata_base64',
      'openvpn_config_data_base64',
      'openvpn config data base64',
      'configdata_base64',
      'config_data_base64',
    ]);
    if (hostIdx == null || ipIdx == null || b64Idx == null) {
      return res.status(502).json({ error: 'Invalid CSV columns' });
    }

    const needle = hostOrIp.toLowerCase();
    let b64 = '';
    for (let i = 1; i < lines.length; i++) {
      const row = lines[i];
      const parts = row.split(',');
      if (parts.length < Math.max(hostIdx, ipIdx, b64Idx) + 1) continue;
      const hn = (parts[hostIdx] || '').trim().toLowerCase();
      const ip = (parts[ipIdx] || '').trim();
      if (hn === needle || ip === hostOrIp.trim()) {
        b64 = (parts[b64Idx] || '').trim();
        if (b64) break;
      }
    }
    if (!b64) return res.status(404).json({ error: 'Config missing' });
    if (!b64) return res.status(404).json({ error: 'Config missing' });
    return res.status(200).json({ host: hostOrIp, ovpnBase64: b64 });
  } catch (e) {
    return res.status(500).json({ error: 'Server error', message: String(e) });
  }
}


