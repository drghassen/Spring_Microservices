#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
: "${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"
export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM}"

temporary_env_file="$(mktemp)"
cleanup_temporary_env_file() {
  rm -f "$temporary_env_file"
}
trap cleanup_temporary_env_file EXIT

cat > "$temporary_env_file" <<'EOF'
# CI build-only placeholders; never use for runtime deployments.
ADMIN_PASSWORD=ci-build-placeholder-admin
DB_PASSWORD=ci-build-placeholder-db
DB_USERNAME=ci-build-placeholder-db-user
JWT_SECRET=ci-build-placeholder-jwt
ME_CONFIG_MONGODB_ADMINPASSWORD=ci-build-placeholder-mongo
ME_CONFIG_MONGODB_ADMINUSERNAME=ci-build-placeholder-mongo-user
MONGO_DB_PASSWORD=ci-build-placeholder-mongo
MONGO_DB_USER=ci-build-placeholder-mongo-user
MONGO_INITDB_ROOT_PASSWORD=ci-build-placeholder-mongo
MONGO_INITDB_ROOT_USERNAME=ci-build-placeholder-mongo-user
PGADMIN_DEFAULT_EMAIL=ci-build-placeholder@example.invalid
PGADMIN_DEFAULT_PASSWORD=ci-build-placeholder-pgadmin
POSTGRES_DB=ci-build-placeholder-db
POSTGRES_PASSWORD=ci-build-placeholder-db
POSTGRES_USER=ci-build-placeholder-db-user
SONAR_JDBC_PASSWORD=ci-build-placeholder-sonar
SONAR_JDBC_USERNAME=ci-build-placeholder-sonar-user
EOF

# Build-time Compose interpolation must never consume local or runtime secrets.
unset ADMIN_PASSWORD DB_PASSWORD DB_USERNAME JWT_SECRET \
  ME_CONFIG_MONGODB_ADMINPASSWORD ME_CONFIG_MONGODB_ADMINUSERNAME \
  MONGO_DB_PASSWORD MONGO_DB_USER MONGO_INITDB_ROOT_PASSWORD \
  MONGO_INITDB_ROOT_USERNAME PGADMIN_DEFAULT_EMAIL PGADMIN_DEFAULT_PASSWORD \
  POSTGRES_DB POSTGRES_PASSWORD POSTGRES_USER SONAR_JDBC_PASSWORD \
  SONAR_JDBC_USERNAME

selected_services=("$@")
if (( ${#selected_services[@]} == 0 )); then
  selected_services=("${APP_SERVICES[@]}")
fi

docker compose --env-file "$temporary_env_file" config -q
docker compose --env-file "$temporary_env_file" build "${selected_services[@]}"

mapfile -t image_references < <(candidate_image_references "${selected_services[@]}")
docker image inspect "${image_references[@]}" >/dev/null

mkdir -p reports
printf '%s\n' "${image_references[@]}" > reports/candidate-image-manifest-"${selected_services[0]}".txt
