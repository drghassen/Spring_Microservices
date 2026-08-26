FROM maven:3.9-eclipse-temurin-17-alpine@sha256:097d7c4ac16bef6c3a8bdc53cf5abe82af5c43547a888a4d2d9f6009fcdcad9f AS deps

WORKDIR /workspace

COPY pom.xml ./
COPY database-migrations/pom.xml database-migrations/pom.xml
COPY config-server/pom.xml config-server/pom.xml
COPY discovery-service/pom.xml discovery-service/pom.xml
COPY gateway/pom.xml gateway/pom.xml
COPY games-service/pom.xml games-service/pom.xml
COPY library-service/pom.xml library-service/pom.xml
COPY order-service/pom.xml order-service/pom.xml
COPY payment-service/pom.xml payment-service/pom.xml
COPY user-service/pom.xml user-service/pom.xml

RUN mvn -B -ntp -pl database-migrations,games-service -am -DskipTests dependency:go-offline

FROM deps AS builder

WORKDIR /workspace

COPY database-migrations/src database-migrations/src
COPY games-service/src games-service/src

RUN mvn -B -ntp -pl games-service -am -DskipTests clean package
RUN java -Djarmode=tools \
    -jar games-service/target/*.jar \
    extract --layers --launcher \
    --destination /workspace/extracted

FROM eclipse-temurin:17.0.20_8-jre-noble@sha256:5726444f65e67c407bac4ff1e036b475051f50bb3840273e81814e77c6fa8ee3 AS runtime

RUN apt-get update && \
    apt-get install --no-install-recommends -y tini wget && \
    rm -rf /var/lib/apt/lists/*

RUN userdel ubuntu && \
    groupadd --gid 1000 spring && \
    useradd --uid 1000 --gid 1000 --no-create-home --home-dir /app --shell /usr/sbin/nologin spring

WORKDIR /app

RUN mkdir -p /app/uploads/games && \
    chown -R spring:spring /app/uploads

COPY --from=builder --chown=spring:spring /workspace/extracted/dependencies/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/application/ ./

USER 1000:1000

EXPOSE 8070

ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8070/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "java", "org.springframework.boot.loader.launch.JarLauncher"]
