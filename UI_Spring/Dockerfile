FROM node:22-alpine@sha256:c610fcdfb1d5b4740dd70c284ed3cb16bb857e0f7166196e36a5501df7a3aa32 AS build

WORKDIR /app

COPY UI_Spring/package.json UI_Spring/package-lock.json ./
RUN npm ci

COPY UI_Spring/ ./
RUN npm run build -- --configuration=production

FROM nginx:stable-alpine@sha256:97d490c12ba55b4946b01546d1c3ed324e8d41ab1c9fcb2a616aa470620e5b46 AS runtime

RUN apk upgrade --no-cache && \
    apk add --no-cache wget && \
    sed -i 's#pid        /run/nginx.pid;#pid        /tmp/nginx.pid;#' /etc/nginx/nginx.conf && \
    chown -R nginx:nginx \
        /usr/share/nginx/html \
        /var/cache/nginx \
        /var/log/nginx \
        /var/run \
        /etc/nginx/conf.d

COPY --from=build --chown=nginx:nginx /app/dist/ui-spring/browser /usr/share/nginx/html
COPY --chown=nginx:nginx UI_Spring/nginx.conf /etc/nginx/conf.d/default.conf

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:8080/ >/dev/null || exit 1

CMD ["nginx", "-g", "daemon off;"]
