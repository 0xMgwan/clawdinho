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

# Create startup script that handles missing auth gracefully
RUN echo '#!/bin/bash\n\
# Create required directories\n\
mkdir -p /data/openclaw /data/workspace\n\
\n\
# Start OpenClaw gateway with error handling\n\
if ! npm start; then\n\
  echo "OpenClaw failed to start, keeping container alive for debugging"\n\
  tail -f /dev/null\n\
fi' > /app/start.sh && chmod +x /app/start.sh

# Health check - just check if container is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=10 \
  CMD ps aux | grep -v grep | grep -q node || exit 1

# Start command
CMD ["/app/start.sh"]
