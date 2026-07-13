# Dev-oriented image for the NestJS backend.
# For production you'd split build/runtime stages; this keeps Phase 0 simple.
FROM node:22-bookworm-slim

# Prisma needs OpenSSL at runtime.
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install deps first for better layer caching.
COPY package.json package-lock.json* ./
RUN npm install

# Prisma schema needed before generate.
COPY prisma ./prisma
RUN npx prisma generate

# App source (in dev this is overlaid by a bind mount in docker-compose).
COPY . .

EXPOSE 3000

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["npm", "run", "start:dev"]
