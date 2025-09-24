FROM node:18-alpine

WORKDIR /app

COPY package*.json ./

RUN npm ci --only=production && npm cache clean --force

RUN addgroup -g 1001 nodejs && adduser -u 1001 -G nodejs -D nodejs

COPY --chown=nodejs:nodejs . .

USER nodejs

EXPOSE 3000

CMD ["npm","start"]

