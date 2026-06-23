FROM node:22-slim

RUN npm install -g @anthropic-ai/claude-code

RUN apt-get update && apt-get install -y --no-install-recommends \
      nmap \
      curl \
    && rm -rf /var/lib/apt/lists/*

COPY trigger-ai-rules.sh /usr/local/bin/trigger-ai-rules
RUN chmod +x /usr/local/bin/trigger-ai-rules

CMD ["sleep", "infinity"]
