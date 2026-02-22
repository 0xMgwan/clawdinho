# OpenClaw Agent - Railway Deployment

This repository contains your OpenClaw AI agent configured for 24/7 deployment on Railway.

## Features
- 🤖 OpenAI GPT-5.2 primary model
- 💰 Bankr DeFi integration 
- 📱 Telegram bot connectivity
- 📞 WhatsApp integration
- ♾️ Morpheus/Everclaw fallback models
- ☁️ 24/7 Railway hosting

## Quick Deploy to Railway

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template)

## Manual Deployment Steps

1. **Create Railway Project**
   ```bash
   railway login
   railway init
   ```

2. **Set Environment Variables**
   - Copy `.env.example` to Railway environment variables
   - Add your actual API keys

3. **Deploy**
   ```bash
   railway up
   ```

## Environment Variables Required

- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `OPENAI_API_KEY` - Your OpenAI API key  
- `TELEGRAM_BOT_TOKEN` - Your Telegram bot token
- `BANKR_API_KEY` - Your Bankr API key

## Local Development

```bash
npm install
npm run dev
```

## Health Check

Your agent will be available at: `https://your-app.railway.app/health`

## Support

- OpenClaw Docs: https://docs.openclaw.ai
- Bankr Integration: https://bankr.bot
- Railway Docs: https://docs.railway.app
