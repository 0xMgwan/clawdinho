FROM node:18-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy OpenClaw config
COPY .openclaw/ ./.openclaw/

# Copy any additional files
COPY . .

# Create necessary directories
RUN mkdir -p /app/.openclaw/workspace
RUN mkdir -p /app/.openclaw/logs

# Set environment
ENV NODE_ENV=production
ENV OPENCLAW_CONFIG_PATH=/app/.openclaw/openclaw.json

# Expose port (Railway will assign one)
EXPOSE 18789

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:18789/health || exit 1

# Start OpenClaw gateway
CMD ["npm", "start"]
