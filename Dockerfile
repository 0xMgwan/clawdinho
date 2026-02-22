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

# Create startup script with better error handling
RUN echo '#!/bin/bash\n\
echo "Starting OpenClaw deployment..."\n\
\n\
# Create required directories\n\
mkdir -p /data/openclaw /data/workspace\n\
\n\
# Wait a moment for environment to stabilize\n\
sleep 5\n\
\n\
# Try to start OpenClaw\n\
echo "Attempting to start OpenClaw gateway..."\n\
npm start 2>&1 | tee /app/openclaw.log &\n\
\n\
# Keep container alive\n\
echo "Container started. OpenClaw logs in /app/openclaw.log"\n\
tail -f /app/openclaw.log' > /app/start.sh && chmod +x /app/start.sh

# Health check - check if Node.js process is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=15 \
  CMD pgrep -f "node" > /dev/null || exit 1

# Start command
CMD ["/app/start.sh"]
