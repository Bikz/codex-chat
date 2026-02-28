FROM node:20-alpine AS build

WORKDIR /app
RUN corepack enable

COPY package.json ./
COPY . ./

RUN pnpm install --no-frozen-lockfile
RUN pnpm build

FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/out /usr/share/nginx/html
