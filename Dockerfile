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

# Create simple Node.js health server
RUN echo 'const http = require("http");\n\
const port = process.env.PORT || 8080;\n\
\n\
console.log(`Container starting at ${new Date()}`);\n\
console.log("Environment check:");\n\
console.log(`OPENAI_API_KEY present: ${process.env.OPENAI_API_KEY ? "YES" : "NO"}`);\n\
console.log(`TELEGRAM_BOT_TOKEN present: ${process.env.TELEGRAM_BOT_TOKEN ? "YES" : "NO"}`);\n\
console.log(`BANKR_API_KEY present: ${process.env.BANKR_API_KEY ? "YES" : "NO"}`);\n\
console.log(`PORT: ${port}`);\n\
\n\
const server = http.createServer((req, res) => {\n\
  console.log(`${new Date().toISOString()} - ${req.method} ${req.url}`);\n\
  \n\
  if (req.url === "/health") {\n\
    res.writeHead(200, { "Content-Type": "application/json" });\n\
    res.end(JSON.stringify({ status: "healthy", service: "openclaw-container", timestamp: new Date().toISOString() }));\n\
  } else {\n\
    res.writeHead(200, { "Content-Type": "text/plain" });\n\
    res.end("OpenClaw container is running");\n\
  }\n\
});\n\
\n\
server.listen(port, "0.0.0.0", () => {\n\
  console.log(`Health server running on 0.0.0.0:${port}`);\n\
  console.log(`Health endpoint: http://0.0.0.0:${port}/health`);\n\
});\n\
\n\
server.on("error", (err) => {\n\
  console.error("Server error:", err);\n\
  process.exit(1);\n\
});' > /app/health-server.js

# Health check - check our HTTP server on Railway's port
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

# Start command - run the Node.js health server
CMD ["node", "/app/health-server.js"]
