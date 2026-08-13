FROM maven:3.9-eclipse-temurin-17-alpine@sha256:097d7c4ac16bef6c3a8bdc53cf5abe82af5c43547a888a4d2d9f6009fcdcad9f AS deps

WORKDIR /workspace

COPY pom.xml ./
COPY discovery-service/pom.xml discovery-service/pom.xml

RUN mvn -B -ntp -f discovery-service/pom.xml -DskipTests dependency:go-offline

FROM deps AS builder

WORKDIR /workspace

COPY discovery-service/src discovery-service/src

RUN mvn -B -ntp -f discovery-service/pom.xml -DskipTests clean package
RUN java -Djarmode=tools \
    -jar discovery-service/target/*.jar \
    extract --layers --launcher \
    --destination /workspace/extracted

FROM eclipse-temurin:17-jre-alpine@sha256:02320dd4ce20e243dfb915c686089cf9315c763084fafbb12d5c9993aee18b57 AS runtime

RUN apk upgrade --no-cache && \
    apk add --no-cache tini wget

RUN addgroup -g 1000 -S spring && \
    adduser -u 1000 -S spring -G spring -h /app -s /sbin/nologin

WORKDIR /app

COPY --from=builder --chown=spring:spring /workspace/extracted/dependencies/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/spring-boot-loader/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/snapshot-dependencies/ ./
COPY --from=builder --chown=spring:spring /workspace/extracted/application/ ./

USER 1000:1000

EXPOSE 8761

ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget -qO- http://localhost:8761/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["/sbin/tini", "--", "java", "org.springframework.boot.loader.launch.JarLauncher"]
