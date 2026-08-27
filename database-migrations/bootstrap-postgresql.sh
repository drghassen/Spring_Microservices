#!/usr/bin/env bash
set -euo pipefail

readonly REQUIRED_VARIABLES=(
  POSTGRES_HOST
  POSTGRES_ADMIN_USERNAME
  POSTGRES_ADMIN_PASSWORD
  POSTGRES_APPLICATION_USERNAME
  POSTGRES_APPLICATION_PASSWORD
)

readonly POSTGRES_PORT="${POSTGRES_PORT:-5432}"
readonly POSTGRES_DATABASE="${POSTGRES_DATABASE:-steam}"
readonly POSTGRES_SSLMODE="${POSTGRES_SSLMODE:-require}"
readonly MIGRATIONS_DIRECTORY="/flyway/sql"

require_environment() {
  local variable_name

  for variable_name in "${REQUIRED_VARIABLES[@]}"; do
    if [[ -z "${!variable_name:-}" ]]; then
      printf 'Required PostgreSQL bootstrap environment variable is missing.\n' >&2
      exit 1
    fi
  done
}

validate_identifier() {
  local identifier="$1"

  if [[ ! "$identifier" =~ ^[a-z_][a-z0-9_]{0,62}$ ]]; then
    printf 'PostgreSQL database and role names must be safe identifiers.\n' >&2
    exit 1
  fi
}

validate_connection_settings() {
  if [[ ! "$POSTGRES_PORT" =~ ^[0-9]{1,5}$ ]] || (( POSTGRES_PORT < 1 || POSTGRES_PORT > 65535 )); then
    printf 'PostgreSQL port must be between 1 and 65535.\n' >&2
    exit 1
  fi

  if [[ "$POSTGRES_SSLMODE" != "require" ]]; then
    printf 'PostgreSQL bootstrap requires POSTGRES_SSLMODE=require.\n' >&2
    exit 1
  fi
}

admin_psql() {
  # POSTGRES_HOST is validated indirectly from REQUIRED_VARIABLES before this function is called.
  # shellcheck disable=SC2153
  PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
    PGSSLMODE="$POSTGRES_SSLMODE" \
    psql \
      --host="$POSTGRES_HOST" \
      --port="$POSTGRES_PORT" \
      --username="$POSTGRES_ADMIN_USERNAME" \
      --dbname="$POSTGRES_DATABASE" \
      --no-password \
      --no-psqlrc \
      --set=ON_ERROR_STOP=1 \
      "$@"
}

wait_for_administrator_connection() {
  for _ in $(seq 1 30); do
    if admin_psql --quiet --command='SELECT 1' >/dev/null 2>&1; then
      return 0
    fi

    sleep 2
  done

  printf 'PostgreSQL administrator connection did not become available.\n' >&2
  exit 1
}

reconcile_application_role() {
  local role_exists
  local escaped_application_password

  role_exists="$(admin_psql --tuples-only --no-align --command="SELECT 1 FROM pg_roles WHERE rolname = '${POSTGRES_APPLICATION_USERNAME}';")"
  escaped_application_password="${POSTGRES_APPLICATION_PASSWORD//\'/\'\'}"

  if [[ "$role_exists" != "1" ]]; then
    printf 'CREATE ROLE "%s" LOGIN PASSWORD '\''%s'\'';\n' \
      "$POSTGRES_APPLICATION_USERNAME" \
      "$escaped_application_password" \
      | admin_psql \
      >/dev/null
  else
    printf 'ALTER ROLE "%s" WITH LOGIN PASSWORD '\''%s'\'';\n' \
      "$POSTGRES_APPLICATION_USERNAME" \
      "$escaped_application_password" \
      | admin_psql \
      >/dev/null
  fi
}

grant_application_permissions() {
  admin_psql \
    --command="GRANT CONNECT ON DATABASE \"${POSTGRES_DATABASE}\" TO \"${POSTGRES_APPLICATION_USERNAME}\"; GRANT USAGE, CREATE ON SCHEMA public TO \"${POSTGRES_APPLICATION_USERNAME}\";" \
    >/dev/null
}

run_flyway_as_application_role() {
  if ! FLYWAY_URL="jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DATABASE}?sslmode=${POSTGRES_SSLMODE}" \
    FLYWAY_USER="$POSTGRES_APPLICATION_USERNAME" \
    FLYWAY_PASSWORD="$POSTGRES_APPLICATION_PASSWORD" \
    flyway \
      -locations="filesystem:${MIGRATIONS_DIRECTORY}" \
      -connectRetries=10 \
      -connectRetriesInterval=2 \
      -cleanDisabled=true \
      -validateMigrationNaming=true \
      migrate \
      >/dev/null 2>&1; then
    printf 'Flyway migration failed.\n' >&2
    exit 1
  fi
}

main() {
  require_environment
  validate_identifier "$POSTGRES_DATABASE"
  validate_identifier "$POSTGRES_ADMIN_USERNAME"
  validate_identifier "$POSTGRES_APPLICATION_USERNAME"
  validate_connection_settings

  wait_for_administrator_connection
  reconcile_application_role
  grant_application_permissions
  run_flyway_as_application_role

  printf 'PostgreSQL bootstrap completed successfully.\n'
}

main "$@"
