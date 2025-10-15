// Cloudflare WARP API endpoint
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export default function handler(req, res) {
  try {
    // Set CORS headers
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
      res.status(200).end();
      return;
    }
    
    if (req.method !== 'GET') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }
    
    // Cloudflare WARP configuration
    const warpConfig = {
      name: "Cloudflare WARP",
      type: "wireguard",
      servers: [
        {
          name: "Cloudflare WARP US",
          endpoint: "engage.cloudflareclient.com:2408",
          publicKey: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          allowedIPs: ["0.0.0.0/0", "::/0"],
          dns: ["1.1.1.1", "1.0.0.1"],
          mtu: 1280,
          persistentKeepalive: 25
        },
        {
          name: "Cloudflare WARP EU",
          endpoint: "engage.cloudflareclient.com:2408",
          publicKey: "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          allowedIPs: ["0.0.0.0/0", "::/0"],
          dns: ["1.1.1.1", "1.0.0.1"],
          mtu: 1280,
          persistentKeepalive: 25
        }
      ],
      description: "Cloudflare WARP - Fast and secure VPN powered by Cloudflare's global network",
      features: [
        "Fastest speeds",
        "Global CDN",
        "Privacy focused",
        "Free tier available"
      ]
    };
    
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    
    res.status(200).json(warpConfig);
    
  } catch (error) {
    console.error('Error serving Cloudflare WARP data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
