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
    
    // Parse CSV to get server count and sample servers
    const lines = csvData.split('\n').filter(line => line.trim() && !line.startsWith('#'));
    const serverCount = Math.max(0, lines.length - 1); // Subtract header
    
    // Parse all servers for VPNGate
    const vpngateServers = [];
    if (lines.length > 1) {
      const header = lines[0].split(',');
      const hostNameIdx = header.findIndex(h => h.toLowerCase().includes('hostname'));
      const ipIdx = header.findIndex(h => h.toLowerCase() === 'ip');
      const countryIdx = header.findIndex(h => h.toLowerCase().includes('countrylong'));
      const scoreIdx = header.findIndex(h => h.toLowerCase() === 'score');
      const pingIdx = header.findIndex(h => h.toLowerCase() === 'ping');
      const speedIdx = header.findIndex(h => h.toLowerCase() === 'speed');
      const base64Idx = header.findIndex(h => h.toLowerCase().includes('openvpn_configdata_base64'));
      
      for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',');
        if (cols.length > Math.max(hostNameIdx, ipIdx, countryIdx, scoreIdx, base64Idx)) {
          const base64 = cols[base64Idx] || '';
          // Only include servers with valid Base64 config
          if (base64.length > 10) {
            vpngateServers.push({
              hostName: cols[hostNameIdx] || 'Unknown',
              ip: cols[ipIdx] || '0.0.0.0',
              country: cols[countryIdx] || 'Unknown',
              score: parseInt(cols[scoreIdx]) || 0,
              ping: parseInt(cols[pingIdx]) || 9999,
              speed: parseInt(cols[speedIdx]) || 0,
              hasConfig: true
            });
          }
        }
      }
    }
    
    // Get sample servers (first 5) for preview
    const sampleServers = vpngateServers.slice(0, 5);
    
    // Unified VPN response
    const unifiedResponse = {
      timestamp: new Date().toISOString(),
      totalServers: serverCount,
      services: {
        vpngate: {
          name: "VPNGate",
          type: "openvpn",
          servers: vpngateServers.length,
          description: "Free OpenVPN servers provided by VPNGate community",
          endpoint: "/api/vpngate",
          features: ["Free", "OpenVPN", "Community-driven", "No registration"],
          sampleServers: sampleServers,
          allServers: vpngateServers
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
          servers: 3,
          description: "Secure and fast VPN powered by Shadowsocks protocol",
          endpoint: "/api/outline-vpn", 
          features: ["Shadowsocks", "High performance", "Easy setup", "Open source", "Multi-region servers"]
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
