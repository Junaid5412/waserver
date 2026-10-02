FROM node:24-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY src ./src
COPY public ./public
COPY sdk ./sdk
COPY scripts ./scripts
COPY test ./test
RUN npm run build
USER node
ENV NODE_ENV=production
EXPOSE 3000
CMD ["node", "src/server.js"]
