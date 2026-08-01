# Official Playwright image ships browsers + OS deps pinned to a Playwright version.
FROM mcr.microsoft.com/playwright:v1.45.0-jammy

ENV NODE_ENV=production
WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev

COPY src ./src

EXPOSE 4000
# Run as the non-root user provided by the base image.
USER pwuser
CMD ["node", "src/server.js"]
