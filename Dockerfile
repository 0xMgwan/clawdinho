FROM node:22

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    python3 \
    curl \
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

# Create startup script that runs both health server and OpenClaw
RUN echo '#!/bin/bash\n\
\n\
echo "=== OpenClaw Railway Deployment Starting ==="\n\
echo "Container starting at $(date)"\n\
echo "Environment check:"\n\
echo "OPENAI_API_KEY present: $(if [ -n "$OPENAI_API_KEY" ]; then echo "YES"; else echo "NO"; fi)"\n\
echo "TELEGRAM_BOT_TOKEN present: $(if [ -n "$TELEGRAM_BOT_TOKEN" ]; then echo "YES"; else echo "NO"; fi)"\n\
echo "BANKR_API_KEY present: $(if [ -n "$BANKR_API_KEY" ]; then echo "YES"; else echo "NO"; fi)"\n\
echo "PORT: ${PORT:-8080}"\n\
\n\
# Create necessary directories\n\
mkdir -p /data/openclaw /data/workspace\n\
mkdir -p /data/openclaw/agents/main/agent\n\
\n\
# Option B: Copy auth-profiles.json from base64 environment variable\n\
if [ -n "$AUTH_PROFILES_BASE64" ]; then\n\
  echo "✅ AUTH_PROFILES_BASE64 is set, creating auth-profiles.json..."\n\
  echo "$AUTH_PROFILES_BASE64" | base64 -d > /data/openclaw/agents/main/agent/auth-profiles.json 2>&1\n\
  if [ -f /data/openclaw/agents/main/agent/auth-profiles.json ]; then\n\
    echo "✅ auth-profiles.json created successfully"\n\
    ls -lh /data/openclaw/agents/main/agent/auth-profiles.json\n\
    echo "📄 File contents (first 500 chars):"\n\
    head -c 500 /data/openclaw/agents/main/agent/auth-profiles.json\n\
    echo ""\n\
    echo "🔍 Checking JSON validity:"\n\
    cat /data/openclaw/agents/main/agent/auth-profiles.json | node -e "try { JSON.parse(require(\"fs\").readFileSync(0, \"utf-8\")); console.log(\"✅ Valid JSON\"); } catch(e) { console.log(\"❌ Invalid JSON:\", e.message); }"\n\
  else\n\
    echo "❌ Failed to create auth-profiles.json"\n\
  fi\n\
else\n\
  echo "❌ AUTH_PROFILES_BASE64 not set - OpenClaw will fail to authenticate"\n\
fi\n\
\n\
# Start health server in background\n\
echo "Starting health server on port ${PORT:-8080}..."\n\
node -e "\n\
const http = require(\"http\");\n\
const port = process.env.PORT || 8080;\n\
\n\
const server = http.createServer((req, res) => {\n\
  if (req.url === \"/health\") {\n\
    res.writeHead(200, { \"Content-Type\": \"application/json\" });\n\
    res.end(JSON.stringify({ status: \"healthy\", service: \"openclaw-railway\", timestamp: new Date().toISOString() }));\n\
  } else {\n\
    res.writeHead(200, { \"Content-Type\": \"text/plain\" });\n\
    res.end(\"OpenClaw Railway Container\");\n\
  }\n\
});\n\
\n\
server.listen(port, \"0.0.0.0\", () => {\n\
  console.log(\`Health server running on 0.0.0.0:\${port}\`);\n\
});\n\
" &\n\
\n\
# Wait for health server to start\n\
sleep 3\n\
\n\
# Test health endpoint\n\
echo "Testing health endpoint..."\n\
curl -f http://localhost:${PORT:-8080}/health && echo "✅ Health check working"\n\
\n\
# Start OpenClaw gateway\n\
echo "Starting OpenClaw gateway..."\n\
export OPENCLAW_CONFIG_PATH=/app/.openclaw/openclaw.json\n\
export OPENCLAW_STATE_DIR=/data/openclaw\n\
export OPENCLAW_WORKSPACE_DIR=/data/workspace\n\
\n\
# Start OpenClaw gateway with minimal options\n\
echo "🦞 Starting OpenClaw Agent for 24/7 operation..."\n\
echo "Using minimal gateway command for older OpenClaw version"\n\
cd /app\n\
npx openclaw gateway\n\
' > /app/start.sh && chmod +x /app/start.sh

# Health check - check our HTTP server on Railway's port
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

# Start command - run the startup script
CMD ["/app/start.sh"]
