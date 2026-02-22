FROM node:22

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy OpenClaw config and workspace
COPY openclaw.json ./.openclaw/openclaw.json
COPY .openclaw-workspace/ ./.openclaw/workspace/

# Copy any additional files
COPY . .

# Create necessary directories
RUN mkdir -p /app/.openclaw/logs

# Set environment
ENV NODE_ENV=production
ENV OPENCLAW_CONFIG_PATH=/app/.openclaw/openclaw.json

# Create startup script for actual OpenClaw
RUN echo '#!/bin/bash\n\
echo "Starting OpenClaw with environment variables..."\n\
echo "Checking required variables..."\n\
\n\
# Check for required API keys\n\
if [ -z "$OPENAI_API_KEY" ]; then\n\
  echo "ERROR: No OpenAI API key found! Need OPENAI_API_KEY"\n\
  exit 1\n\
fi\n\
\n\
echo "API keys found, starting OpenClaw..."\n\
echo "Telegram bot token: ${TELEGRAM_BOT_TOKEN:0:10}..."\n\
echo "Bankr API key: ${BANKR_API_KEY:0:10}..."\n\
\n\
# Create required directories\n\
mkdir -p /data/openclaw /data/workspace\n\
\n\
# Start OpenClaw\n\
exec npm start' > /app/start.sh && chmod +x /app/start.sh

# Health check - check if OpenClaw gateway is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
  CMD curl -f http://localhost:18789/health || exit 1

# Start command
CMD ["/app/start.sh"]
