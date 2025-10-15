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
    const __filename = fileURLToPath(import.meta.url);
    const __dirname = path.dirname(__filename);
    const fs = await import('fs');
    const csvPath = path.join(__dirname, '..', 'vpngate.csv');
    const csv = fs.readFileSync(csvPath, 'utf8');
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


