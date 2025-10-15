# Vyntra VPN - Serverless VPN App

A free, serverless VPN app for Android built with Flutter, using Vercel API for server data.

## Features

- 🚀 **Free & Serverless** - No server setup required
- 🔒 **Secure OpenVPN** - Uses VPNGate servers
- 🌙 **Dark/Light Mode** - Switchable themes
- ⚡ **Fast Connection** - Optimized server selection
- 🔄 **Auto-Reconnect** - Persistent connection
- ⏰ **1-Hour Sessions** - Free usage limit
- 📱 **Android Only** - Optimized for mobile

## API Endpoint

The app fetches VPN server data from: `https://vyntra-vpn.vercel.app/api/vpngate`

## Deployment

This repository contains the Vercel API files:
- `api/vpngate.js` - API endpoint serving VPN server data
- `vpngate.csv` - VPN server database (101 servers)
- `package.json` - Node.js configuration
- `vercel.json` - Vercel deployment config

## Developer

**Aiks - Aikya Naskar**

## License

Free for personal use.