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

    // Prefer live CSV (VPNGate iPhone API). Fallback to bundled CSV only if live fails
    let csv = null;
    try {
      const bypassHeader = req.headers['x-vercel-protection-bypass'];
      const headers = {
        'User-Agent': 'Vyntra-VPN-Android/1.0',
        'Accept': 'text/plain,*/*',
        'Cache-Control': 'no-cache',
      };
      if (bypassHeader) headers['X-Vercel-Protection-Bypass'] = bypassHeader;
      const urls = [
        'https://www.vpngate.net/api/iphone/',
        'http://www.vpngate.net/api/iphone/',
        'http://vpngate.net/api/iphone/'
      ];
      for (const u of urls) {
        try {
          const resp = await fetch(u, { headers, cache: 'no-store' });
          const text = await resp.text();
          if (resp.ok && text && /hostname/i.test(text)) { csv = text; break; }
        } catch (_) { /* try next */ }
      }
    } catch (_) { /* ignore and fallback */ }

    if (!csv) {
      const candidates = [
        path.join(__dirname, 'vpngate.csv'),
        path.join(__dirname, '..', 'vpngate.csv'),
        path.join(__dirname, '..', 'data', 'vpngate.csv'),
        path.join(process.cwd(), 'data', 'vpngate.csv'),
        path.join(process.cwd(), 'vyntra_app_aiks', 'data', 'vpngate.csv'),
      ];
      for (const p of candidates) {
        try {
          if (fs.existsSync(p)) {
            csv = fs.readFileSync(p, 'utf8');
            break;
          }
        } catch (_) { /* ignore */ }
      }
      if (!csv) return res.status(502).json({ error: 'Unable to load VPNGate CSV (no live and no local)' });
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
    
    // Debug: log the header columns we found
    console.log('Header columns:', cols);
    console.log('Lower columns:', lower);
    
    const findColIncludes = (needles) => {
      for (let i = 0; i < lower.length; i++) {
        const cell = lower[i];
        for (const n of needles) {
          if (cell.includes(n)) return i;
        }
      }
      return -1;
    };

    const hostIdx = findColIncludes(['hostname']);
    const ipIdx = findColIncludes(['ip']);
    const b64Idx = findColIncludes(['openvpn_configdata_base64']);
    
    console.log('Column indices:', { hostIdx, ipIdx, b64Idx });
    
    if (hostIdx == null || ipIdx == null || b64Idx == null) {
      return res.status(502).json({ error: 'Invalid CSV columns', debug: { cols, lower, hostIdx, ipIdx, b64Idx } });
    }

    // CSV row splitter supporting quoted fields with commas
    const splitCsvRow = (row) => {
      const out = [];
      let cur = '';
      let inQ = false;
      for (let i = 0; i < row.length; i++) {
        const ch = row[i];
        if (ch === '"') {
          // toggle quote or escape double quote
          if (inQ && row[i + 1] === '"') { cur += '"'; i++; }
          else inQ = !inQ;
        } else if (ch === ',' && !inQ) {
          out.push(cur); cur = '';
        } else {
          cur += ch;
        }
      }
      out.push(cur);
      return out;
    };

    const needle = hostOrIp.toLowerCase();
    let b64 = '';
    let debugInfo = { totalRows: lines.length - 1, hostIdx, ipIdx, b64Idx, needle, checked: 0 };
    
    for (let i = 1; i < lines.length; i++) {
      const row = lines[i];
      const parts = splitCsvRow(row);
      if (parts.length < Math.max(hostIdx, ipIdx, b64Idx) + 1) continue;
      const trimQuotes = (s) => (s || '').trim().replace(/^"|"$/g, '');
      const hn = trimQuotes(parts[hostIdx]).toLowerCase();
      const ip = trimQuotes(parts[ipIdx]);
      debugInfo.checked++;
      
      if (hn === needle || ip === hostOrIp.trim()) {
        b64 = (parts[b64Idx] || '').trim();
        debugInfo.found = { hn, ip, b64Length: b64.length };
        if (b64) break;
      }
    }
    
    if (!b64) {
      console.log('Debug info:', JSON.stringify(debugInfo));
      return res.status(404).json({ error: 'Config missing', debug: debugInfo });
    }
    return res.status(200).json({ host: hostOrIp, ovpnBase64: b64 });
  } catch (e) {
    return res.status(500).json({ error: 'Server error', message: String(e) });
  }
}


