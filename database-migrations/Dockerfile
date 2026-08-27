FROM docker.io/flyway/flyway:13.3.0-alpine@sha256:fb13953f16913efd313f202ec4b4ed34fd2ea14cc51401eb36ea9818c0df2918

RUN apk upgrade --no-cache \
    && apk add --no-cache postgresql17-client \
    && find /flyway/drivers -mindepth 1 -maxdepth 1 \
        ! -name 'postgresql-42.7.12.jar' -exec rm -rf {} + \
    && for plugin in /flyway/lib/flyway/flyway-database-*.jar; do \
        case "$plugin" in \
          */flyway-database-postgresql-13.3.0.jar) ;; \
          *) rm -f -- "$plugin" ;; \
        esac; \
      done \
    && rm -f -- \
        /flyway/lib/flyway/flyway-firebird-*.jar \
        /flyway/lib/flyway/flyway-gcp-*.jar \
        /flyway/lib/flyway/flyway-locations-s3-*.jar \
        /flyway/lib/flyway/flyway-mysql-*.jar \
        /flyway/lib/flyway/flyway-nc-*.jar \
        /flyway/lib/flyway/flyway-singlestore-*.jar \
        /flyway/lib/flyway/flyway-sqlserver-*.jar \
    && addgroup -S -g 10001 migrator \
    && adduser -S -D -H -u 10001 -G migrator migrator

COPY src/main/resources/db/migration/V1__initial_steam_schema.sql /flyway/migrations/V1__initial_steam_schema.sql
COPY bootstrap-postgresql.sh /usr/local/bin/bootstrap-postgresql

RUN chmod 0555 /usr/local/bin/bootstrap-postgresql \
    && mkdir -p /var/lib/migrator/.flyway \
    && chown -R migrator:migrator /var/lib/migrator \
    && chmod 0700 /var/lib/migrator/.flyway

ENV PATH="/flyway:${PATH}" \
    HOME="/var/lib/migrator"

WORKDIR /var/lib/migrator

USER 10001:10001

ENTRYPOINT ["/usr/local/bin/bootstrap-postgresql"]
