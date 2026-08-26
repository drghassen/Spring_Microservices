#!/bin/sh
set -eu

case "${NGINX_DEPLOYMENT_TARGET:-docker}" in
  docker)
    source_config="/etc/nginx/ladhari/nginx.docker.conf"
    ;;
  aca)
    source_config="/etc/nginx/ladhari/nginx.aca.conf"
    ;;
  *)
    printf >&2 'Unsupported NGINX_DEPLOYMENT_TARGET: %s\n' \
      "${NGINX_DEPLOYMENT_TARGET}"
    exit 64
    ;;
esac

cp "$source_config" /etc/nginx/conf.d/default.conf

nginx -t

exec "$@"
