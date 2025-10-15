// Outline VPN API endpoint
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
    
    // Outline VPN configuration
    const outlineConfig = {
      name: "Outline VPN",
      type: "shadowsocks",
      servers: [
        {
          name: "Outline Server 1",
          hostname: "outline-server-1.example.com",
          port: 443,
          method: "chacha20-ietf-poly1305",
          password: "outline-password-1",
          description: "High-speed Outline server"
        },
        {
          name: "Outline Server 2", 
          hostname: "outline-server-2.example.com",
          port: 443,
          method: "chacha20-ietf-poly1305",
          password: "outline-password-2",
          description: "Reliable Outline server"
        }
      ],
      description: "Outline VPN - Secure and fast VPN powered by Shadowsocks",
      features: [
        "Shadowsocks protocol",
        "High performance",
        "Easy setup",
        "Open source"
      ],
      setupInstructions: {
        step1: "Download Outline client",
        step2: "Add server configuration",
        step3: "Connect and enjoy secure browsing"
      }
    };
    
    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    
    res.status(200).json(outlineConfig);
    
  } catch (error) {
    console.error('Error serving Outline VPN data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
