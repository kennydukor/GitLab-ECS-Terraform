FROM node:15.10-slim AS build
WORKDIR /app
ADD package.json .
RUN npm install

FROM node:15.10-slim
ENV NODE_ENV production
ENV PORT 80
WORKDIR /app
COPY --from=build /app .
ADD . .
EXPOSE 80
CMD ["node", "index.js"]
