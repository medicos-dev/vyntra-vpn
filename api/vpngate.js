// Vercel API endpoint for VPN servers
import fs from 'fs';
import path from 'path';

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
    
    // Read the CSV file
    const csvPath = path.join(process.cwd(), 'vpngate.csv');
    const csvData = fs.readFileSync(csvPath, 'utf8');
    
    // Set headers for CSV response
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600'); // Cache for 1 hour
    
    res.status(200).send(csvData);
    
  } catch (error) {
    console.error('Error serving VPN data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
}
