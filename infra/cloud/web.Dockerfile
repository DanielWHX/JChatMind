FROM node:22-alpine AS build
WORKDIR /build
COPY ui/package.json ui/package-lock.json ./
RUN npm ci
COPY ui/ ./
RUN npm run build

FROM nginx:1.28-alpine
COPY --from=build /build/dist /usr/share/nginx/html
COPY infra/cloud/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY infra/cloud/guest-proxy.conf /etc/nginx/snippets/guest-proxy.conf
COPY infra/cloud/15-admin-auth-check.sh /docker-entrypoint.d/15-admin-auth-check.sh
RUN chmod 755 /docker-entrypoint.d/15-admin-auth-check.sh
EXPOSE 80
