// Unified VPN API - combines VPNGate, Cloudflare WARP, and Outline VPN
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
    
    const { type } = req.query;
    
    // Read VPNGate CSV data
    const csvPath = path.join(__dirname, '..', 'vpngate.csv');
    const csvData = fs.readFileSync(csvPath, 'utf8');
    
    // Parse CSV to get server count
    const lines = csvData.split('\n').filter(line => line.trim() && !line.startsWith('#'));
    const serverCount = Math.max(0, lines.length - 1); // Subtract header
    
    // Unified VPN response
    const unifiedResponse = {
      timestamp: new Date().toISOString(),
      totalServers: serverCount,
      services: {
        vpngate: {
          name: "VPNGate",
          type: "openvpn",
          servers: serverCount,
          description: "Free OpenVPN servers provided by VPNGate community",
          endpoint: "/api/vpngate",
          features: ["Free", "OpenVPN", "Community-driven", "No registration"]
        },
        cloudflareWarp: {
          name: "Cloudflare WARP",
          type: "wireguard", 
          servers: 2,
          description: "Fast and secure VPN powered by Cloudflare's global network",
          endpoint: "/api/cloudflare-warp",
          features: ["Fastest speeds", "Global CDN", "Privacy focused", "Free tier"]
        },
        outlineVpn: {
          name: "Outline VPN",
          type: "shadowsocks",
          servers: 2,
          description: "Secure and fast VPN powered by Shadowsocks protocol",
          endpoint: "/api/outline-vpn", 
          features: ["Shadowsocks", "High performance", "Easy setup", "Open source"]
        }
      },
      recommendations: {
        fastest: "cloudflareWarp",
        mostSecure: "outlineVpn", 
        mostServers: "vpngate",
        bestForMobile: "cloudflareWarp"
      },
      developer: "Aiks - Aikya Naskar"
    };
    
    // Return specific service if requested
    if (type === 'vpngate') {
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.status(200).send(csvData);
    } else if (type === 'cloudflare-warp') {
      res.setHeader('Content-Type', 'application/json');
      res.status(200).json(unifiedResponse.services.cloudflareWarp);
    } else if (type === 'outline-vpn') {
      res.setHeader('Content-Type', 'application/json');
      res.status(200).json(unifiedResponse.services.outlineVpn);
    } else {
      // Return unified response
      res.setHeader('Content-Type', 'application/json');
      res.setHeader('Cache-Control', 'public, max-age=1800'); // Cache for 30 minutes
      res.status(200).json(unifiedResponse);
    }
    
  } catch (error) {
    console.error('Error serving unified VPN data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
