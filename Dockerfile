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

# Create startup script that always works
RUN echo '#!/bin/bash\n\
echo "Container starting at $(date)"\n\
echo "Environment check:"\n\
echo "OPENAI_API_KEY present: $(if [ -n "$OPENAI_API_KEY" ]; then echo "YES"; else echo "NO"; fi)"\n\
echo "TELEGRAM_BOT_TOKEN present: $(if [ -n "$TELEGRAM_BOT_TOKEN" ]; then echo "YES"; else echo "NO"; fi)"\n\
echo "BANKR_API_KEY present: $(if [ -n "$BANKR_API_KEY" ]; then echo "YES"; else echo "NO"; fi)"\n\
\n\
# Create directories\n\
mkdir -p /data/openclaw /data/workspace\n\
\n\
# Start simple HTTP server for health checks on Railway's expected port\n\
PORT=${PORT:-8080}\n\
echo "Starting HTTP server on 0.0.0.0:$PORT (Railway port)..."\n\
python3 -c "\n\
import http.server\n\
import socketserver\n\
import os\n\
import threading\n\
import time\n\
\n\
class HealthHandler(http.server.SimpleHTTPRequestHandler):\n\
    def do_GET(self):\n\
        if self.path == \"/health\":\n\
            self.send_response(200)\n\
            self.send_header(\"Content-type\", \"application/json\")\n\
            self.end_headers()\n\
            self.wfile.write(b\"{\\"status\\": \\"healthy\\", \\"service\\": \\"openclaw-container\\"}\")\n\
        else:\n\
            self.send_response(200)\n\
            self.send_header(\"Content-type\", \"text/plain\")\n\
            self.end_headers()\n\
            self.wfile.write(b\"OpenClaw container is running\")\n\
    \n\
    def log_message(self, format, *args):\n\
        print(f\"Health check: {format % args}\")\n\
\n\
PORT = int(os.environ.get(\"PORT\", 8080))\n\
print(f\"Binding health server to 0.0.0.0:{PORT}\")\n\
try:\n\
    with socketserver.TCPServer((\"0.0.0.0\", PORT), HealthHandler) as httpd:\n\
        print(f\"Health server successfully started on 0.0.0.0:{PORT}\")\n\
        httpd.serve_forever()\n\
except Exception as e:\n\
    print(f\"Failed to start health server: {e}\")\n\
    import traceback\n\
    traceback.print_exc()\n\
" &\n\
\n\
# Give the server time to start\n\
sleep 2\n\
\n\
# Test if server is responding\n\
echo "Testing health endpoint..."\n\
curl -f http://localhost:$PORT/health || echo "Health endpoint not responding yet"\n\
\n\
# Keep container alive\n\
echo "Container ready - health server running in background"\n\
tail -f /dev/null' > /app/start.sh && chmod +x /app/start.sh

# Health check - check our HTTP server on Railway's port
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

# Start command
CMD ["/app/start.sh"]
