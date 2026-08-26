FROM flyway/flyway:11.17.1 AS flyway

RUN curl --fail --silent --show-error --location \
    --output /tmp/flyway-database-postgresql-11.17.1.jar \
    https://repo1.maven.org/maven2/org/flywaydb/flyway-database-postgresql/11.17.1/flyway-database-postgresql-11.17.1.jar \
    && echo "7456d20a7fdc1c0e4cd84edd99b55ed744b49eba559480f2630257842bdff805  /tmp/flyway-database-postgresql-11.17.1.jar" | sha256sum --check \
    && install --mode=0644 /tmp/flyway-database-postgresql-11.17.1.jar /flyway/drivers/flyway-database-postgresql-11.17.1.jar \
    && rm --force /tmp/flyway-database-postgresql-11.17.1.jar

FROM postgres:16.10-bookworm

RUN apt-get update \
    && apt-get install --yes --no-install-recommends openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

COPY --from=flyway /flyway /flyway
COPY src/main/resources/db/migration/V1__initial_steam_schema.sql /flyway/sql/V1__initial_steam_schema.sql
COPY bootstrap-postgresql.sh /usr/local/bin/bootstrap-postgresql

RUN chmod 0555 /usr/local/bin/bootstrap-postgresql

ENV PATH="/flyway:${PATH}"

ENTRYPOINT ["/usr/local/bin/bootstrap-postgresql"]
