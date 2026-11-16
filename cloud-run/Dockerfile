FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json ./
COPY server.mjs ./
COPY src ./src
USER node
EXPOSE 8080
CMD ["npm", "start"]
