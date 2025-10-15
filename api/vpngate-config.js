import { fileURLToPath } from 'url';
import path from 'path';

// Fetch helper with Node 18+ global fetch
async function fetchIphoneCsv() {
  const urls = [
    'http://www.vpngate.net/api/iphone/',
    'http://vpngate.net/api/iphone/'
  ];
  for (const u of urls) {
    const res = await fetch(u, {
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36',
        'Accept': 'text/plain,*/*'
      },
      cache: 'no-store'
    });
    if (res.ok) {
      const txt = await res.text();
      if (txt && txt.includes('HostName')) return txt;
    }
  }
  throw new Error('VPNGate CSV fetch failed');
}

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();

  const hostOrIp = (req.query.host || '').toString().trim();
  if (!hostOrIp) return res.status(400).json({ error: 'host is required' });
  try {
    const csv = await fetchIphoneCsv();
    const lines = csv.split(/\r?\n/).filter(l => l && !l.startsWith('#') && !l.startsWith('*'));
    const header = lines.find(l => /HostName,/i.test(l));
    if (!header) return res.status(502).json({ error: 'Invalid CSV' });
    const cols = header.split(',');
    const idx = Object.fromEntries(cols.map((c, i) => [c.trim(), i]));
    const want = lines.find(l => {
      const parts = l.split(',');
      const hn = parts[idx['HostName']] || '';
      const ip = parts[idx['IP']] || '';
      return hn.trim().toLowerCase() === hostOrIp.toLowerCase() || ip.trim() === hostOrIp;
    });
    if (!want) return res.status(404).json({ error: 'Not found' });
    const parts = want.split(',');
    const b64 = (parts[idx['OpenVPN_ConfigData_Base64']] || '').trim();
    if (!b64) return res.status(404).json({ error: 'Config missing' });
    return res.status(200).json({ host: hostOrIp, ovpnBase64: b64 });
  } catch (e) {
    return res.status(500).json({ error: 'Server error', message: String(e) });
  }
}


