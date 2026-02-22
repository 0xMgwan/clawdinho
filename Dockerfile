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

# Create simple startup script that bypasses OpenClaw issues
RUN echo '#!/bin/bash\n\
echo "=== OpenClaw Startup Debug ==="\n\
echo "Environment variables:"\n\
env | sort\n\
echo "=== Starting OpenClaw ==="\n\
\n\
# Create required directories\n\
mkdir -p /data/openclaw /data/workspace\n\
\n\
# Try to start OpenClaw and capture output\n\
echo "Running: npm start"\n\
npm start 2>&1 | tee /app/openclaw.log\n\
\n\
echo "=== OpenClaw exited ==="\n\
echo "Logs:"\n\
cat /app/openclaw.log\n\
\n\
# Keep container alive for debugging\n\
echo "Keeping container alive..."\n\
tail -f /dev/null' > /app/start.sh && chmod +x /app/start.sh

# Health check - just check if container is running
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD ps aux | grep -v grep | grep -q "npm\\|node" || exit 1

# Start command
CMD ["/app/start.sh"]
