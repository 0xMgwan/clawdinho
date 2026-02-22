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

# Create startup script
RUN echo '#!/bin/bash\n\
# Wait for dependencies\n\
sleep 10\n\
\n\
# Start OpenClaw gateway\n\
exec npm start' > /app/start.sh && chmod +x /app/start.sh

# Health check - check if process is running instead of HTTP endpoint
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
  CMD pgrep -f "openclaw" || exit 1

# Start command
CMD ["/app/start.sh"]
