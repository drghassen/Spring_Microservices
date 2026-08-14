# DevSecOps Work Summary

Date: 2026-08-13
Branch: `devsecops-docker-optimization`
Last committed baseline: `21c8720 chore: optimize docker images and local deployment fixes [skip ci]`

This document summarizes the DevSecOps work done on the Spring microservices project, the current verified state, and the recommended next step for a CircleCI pipeline.

## Project Scope

The project contains:

- Backend Spring Boot microservices:
  - `config-server`
  - `discovery-service`
  - `gateway`
  - `games-service`
  - `library-service`
  - `order-service`
  - `payment-service`
  - `user-service`
- Frontend Angular app:
  - `UI_Spring`
- Local orchestration:
  - `docker-compose.yml`
- Quality and security tools:
  - SonarQube
  - Trivy

Kubernetes/Helm is currently out of scope for this phase because this task is focused on Docker, local validation, image security, and CI preparation.

## What We Did

### 1. Docker Image Optimization

All backend Dockerfiles were reviewed and optimized with a production-oriented approach.

Main improvements:

- Multi-stage builds.
- Maven build stage separated from Java runtime stage.
- Runtime image uses JRE instead of Maven.
- Base images pinned by digest.
- Spring Boot layered jar extraction.
- Non-root runtime user.
- `tini` used as init process.
- Healthchecks added per service.
- JVM container options added through `JAVA_TOOL_OPTIONS`.
- Upload directories prepared only for services that need them.
- Dockerfiles are compatible with root build context.

Important rule:

```bash
docker build -f service-name/Dockerfile .
```

or:

```bash
docker compose build
```

Do not build backend images from inside each service folder, because the optimized Dockerfiles expect the repository root as build context.

### 2. Frontend Docker Optimization

The Angular frontend image was optimized with:

- Node build stage.
- Nginx runtime stage.
- Non-root Nginx user.
- Custom Nginx config.
- Healthcheck.
- Production Angular build.

Current frontend image size:

```text
ghassen_dridi/client:21c8720   115MB
```

### 3. Docker Compose Compatibility

`docker-compose.yml` was adjusted to use dynamic image names and dynamic tags:

```yaml
image: ${IMAGE_REPOSITORY_PREFIX:-ghassen_dridi}/service-name:${IMAGE_TAG:-local}
```

This allows local builds, CI builds, DockerHub, or Azure Container Registry without editing the compose file every time.

Recommended local build variables:

```bash
export IMAGE_TAG=$(git rev-parse --short HEAD)
export IMAGE_REPOSITORY_PREFIX=ghassen_dridi
```

Recommended CircleCI tag:

```bash
export IMAGE_TAG=${CIRCLE_SHA1}
export IMAGE_REPOSITORY_PREFIX=ghassen_dridi
```

For Azure Container Registry:

```bash
export IMAGE_REPOSITORY_PREFIX="$ACR_LOGIN_SERVER"
export IMAGE_TAG=${CIRCLE_SHA1}
```

### 4. Docker Environment Cleanup

Old images using the previous repository prefix were identified.

Current clean target image set:

```text
ghassen_dridi/config-server:21c8720
ghassen_dridi/discovery-service:21c8720
ghassen_dridi/gateway:21c8720
ghassen_dridi/games-service:21c8720
ghassen_dridi/library-service:21c8720
ghassen_dridi/order-service:21c8720
ghassen_dridi/payment-service:21c8720
ghassen_dridi/user-service:21c8720
ghassen_dridi/client:21c8720
```

Note:

`mongo:7` and `mongo:latest` can point to the same image ID. This is not a duplicate binary image; it is the same image with two tags.

### 5. Local Container Validation

The application was started locally using Docker Compose.

Currently observed running application containers:

```text
client                       ghassen_dridi/client:21c8720              healthy
config-server                ghassen_dridi/config-server:21c8720       healthy
discovery-service            ghassen_dridi/discovery-service:21c8720   healthy
gateway                      ghassen_dridi/gateway:21c8720             healthy
games-service                ghassen_dridi/games-service:21c8720       healthy
library-service              ghassen_dridi/library-service:21c8720     healthy
order-service                ghassen_dridi/order-service:21c8720       healthy
payment-service              ghassen_dridi/payment-service:21c8720     healthy
user-service                 ghassen_dridi/user-service:21c8720        healthy
```

Local access points:

```text
Frontend:       http://localhost/
Gateway:        http://localhost:8222
Eureka:         http://localhost:8761
Config Server:  http://localhost:8888
SonarQube:      http://localhost:9000
```

When using a VM, WSL, or remote host IP, replace `localhost` with the host IP.

### 6. API Gateway and CORS Hardening

SonarQube reported a security hotspot:

```text
java:S5122 - permissive CORS policy
```

The gateway had permissive CORS:

```java
configuration.addAllowedOrigin("*");
configuration.addAllowedMethod("*");
configuration.addAllowedHeader("*");
```

This was replaced by an explicit CORS policy:

- No wildcard origin.
- No wildcard method.
- No wildcard header.
- Credentials disabled.
- Allowed origins configurable through environment/config.

Main files:

```text
gateway/src/main/java/org/springboot/gateway/config/CorsConfig.java
config-server/src/main/resources/configs/gateway.yml
gateway/src/test/java/org/springboot/gateway/config/CorsConfigTests.java
```

If the frontend IP changes, update the allowed origins through environment variables instead of changing code:

```bash
CORS_ALLOWED_ORIGINS=http://localhost,http://localhost:4200,http://127.0.0.1:4200,http://YOUR_HOST_IP
```

### 7. SonarQube Quality Gate Fixes

Initial Quality Gate failed because:

```text
Coverage on New Code < 80%
Duplicated Lines on New Code > 3%
```

Fixes applied:

- Added focused backend unit tests.
- Improved JaCoCo report path for multi-module Maven.
- Reduced duplication in `GamesService`.
- Fixed Sonar code smells:
  - JUnit 5 test visibility rule `java:S5786`.
  - Deprecated Spring Security API usage `java:S1874`.

Important files:

```text
pom.xml
games-service/src/main/java/org/springboot/gamesservice/services/GamesService.java
games-service/src/test/java/org/springboot/gamesservice/services/GamesServiceTests.java
games-service/src/test/java/org/springboot/gamesservice/controller/AdminGameControllerTests.java
games-service/src/test/java/org/springboot/gamesservice/exception/GlobalExceptionHandlerTests.java
gateway/src/test/java/org/springboot/gateway/GatewayFilterRolesTests.java
gateway/src/test/java/org/springboot/gateway/GatewayAuthFilter.java
user-service/src/main/java/org/springboot/userservice/config/ApplicationConfig.java
user-service/src/test/java/org/springboot/userservice/services/UserServiceTests.java
```

Final verified Sonar state:

```text
Quality Gate: OK
New Coverage: 82.8%
New Duplicated Lines Density: 0.0%
Rules java:S5786 and java:S1874: 0 open issues
```

### 8. Maven Build Verification

The full backend build was verified:

```bash
mvn -B -ntp verify
```

Final result:

```text
config-server       SUCCESS
discovery-service   SUCCESS
gateway             SUCCESS
games-service       SUCCESS
library-service     SUCCESS
order-service       SUCCESS
payment-service     SUCCESS
user-service        SUCCESS

BUILD SUCCESS
```

### 9. SonarQube Scan Command

Use this after `mvn verify`:

```bash
mvn -B -ntp org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  -Dsonar.projectKey=Internship-Proxym \
  -Dsonar.projectName="Internship Proxym" \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300
```

Do not use:

```bash
mvn sonar:sonar
```

because the local Maven setup may not resolve the `sonar` plugin prefix.

Security note:

If a Sonar token was printed in terminal logs or shared accidentally, revoke it and create a new one.

### 10. Trivy Scans

Trivy was used for:

- Repository filesystem scan.
- Docker image scan.
- Vulnerability detection.
- Secret detection.
- Misconfiguration detection.

Existing report directory:

```text
trivy-reports/
```

Recommended filesystem scan:

```bash
trivy fs \
  --scanners vuln,secret,misconfig \
  --severity LOW,MEDIUM,HIGH,CRITICAL \
  --no-progress \
  --timeout 20m \
  .
```

Recommended blocking filesystem scan for CI:

```bash
trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  --timeout 20m \
  .
```

Recommended image scan:

```bash
trivy image \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  --timeout 20m \
  ghassen_dridi/gateway:21c8720
```

## Current Git State

Current branch:

```text
devsecops-docker-optimization
```

Committed baseline:

```text
21c8720 chore: optimize docker images and local deployment fixes [skip ci]
```

There are still uncommitted changes after the latest Sonar/CORS/test fixes.

Modified files include:

```text
config-server/src/main/resources/configs/gateway.yml
docker-compose.yml
games-service/src/main/java/org/springboot/gamesservice/services/GamesService.java
games-service/src/test/java/org/springboot/gamesservice/services/GamesServiceTests.java
gateway/src/main/java/org/springboot/gateway/config/CorsConfig.java
gateway/src/test/java/org/springboot/gateway/GatewayAuthFilter.java
gateway/src/test/java/org/springboot/gateway/GatewayFilterRolesTests.java
pom.xml
user-service/src/main/java/org/springboot/userservice/config/ApplicationConfig.java
```

New untracked files include:

```text
games-service/src/test/java/org/springboot/gamesservice/controller/
games-service/src/test/java/org/springboot/gamesservice/exception/
gateway/src/test/java/org/springboot/gateway/config/
user-service/src/test/java/org/springboot/userservice/services/UserServiceTests.java
trivy-reports/ghassen_dridi_*.txt
```

Before pushing, review and commit the current changes.

## CircleCI Status

The CI implementation is now versioned in `.circleci/config.yml`.
The YAML file orchestrates jobs only; the executable steps are maintained in `.circleci/scripts/` so they can be reviewed and syntax-checked independently.

The `backend-quality` job runs on the `drghassen/sonar-vm` CircleCI machine runner, installed on the VM that hosts the local SonarQube container. The CircleCI `sonarqube` context must therefore define `SONAR_HOST_URL=http://127.0.0.1:9000` and a private `SONAR_TOKEN`.

It keeps the responsibilities separated:

- backend tests, JaCoCo coverage, SonarQube quality gate, Angular headless tests and production frontend build;
- Trivy filesystem, secret, IaC and image scans that block on HIGH/CRITICAL findings;
- CycloneDX SBOM generation for every application image;
- Docker Compose smoke tests, Eureka registration assertions and passive OWASP ZAP baseline scans;
- immutable full-SHA image push to Azure Container Registry only after all gates pass on `master`.

## Recommended CircleCI Pipeline

Professional pipeline order:

```text
checkout
backend_tests_and_sonarqube_quality_gate ─┐
frontend_headless_tests_and_build          ├─> build_images_once
trivy_filesystem_scan                     ─┘        ↓
                                             SBOM_and_trivy_image_scan
                                                        ↓
                                             docker_compose_and_eureka_checks
                                                        ↓
                                             OWASP_ZAP_baseline_scan
                                                        ↓
                                             push_same_images_to_ACR_on_master
```

All three first gates run in parallel. Non-`master` branches run the full container qualification with local `ci.local` image tags. `master` runs the same qualification and pushes those exact local image tags to ACR in the same machine job: images are not rebuilt after scanning.

### Stage 1 - Backend Tests, Coverage and SonarQube

```bash
mvn -B -ntp clean verify
```

The job then runs SonarQube against the JaCoCo reports produced by `verify` and blocks on the configured quality gate.

### Stage 2 - Frontend Tests and Build

```bash
cd UI_Spring
npm ci
npm run test -- --watch=false --browsers=ChromeHeadless
npm run build -- --configuration=production
```

### Stage 3 - Trivy Filesystem Scan

Blocking mode:

```bash
trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  --timeout 20m \
  .
```

### Stage 4 - Docker Build

```bash
export IMAGE_TAG=${CIRCLE_SHA1}
export IMAGE_REPOSITORY_PREFIX=ghassen_dridi

docker compose build
```

### Stage 5 - SBOM and Trivy Image Scan

Example:

```bash
for image in \
  config-server \
  discovery-service \
  gateway \
  games-service \
  library-service \
  order-service \
  payment-service \
  user-service \
  client
do
  trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --no-progress \
    --timeout 20m \
    "${IMAGE_REPOSITORY_PREFIX}/${image}:${IMAGE_TAG}"
done
```

The pipeline also writes a CycloneDX SBOM for every image before enforcing the Trivy vulnerability gate.

### Stage 6 - Docker Compose, Eureka and ZAP

Start only the application stack:

```bash
docker compose up -d --no-build \
  mongodb \
  postgresql \
  config-server \
  discovery-service \
  gateway \
  games-service \
  library-service \
  order-service \
  payment-service \
  user-service \
  client
```

Health checks:

```bash
curl -f http://localhost:8888/actuator/health
curl -f http://localhost:8761/actuator/health
curl -f http://localhost:8222/actuator/health
curl -f http://localhost/
```

The CI then waits until Eureka reports exactly one instance for each expected application and runs passive ZAP baseline scans against the client and gateway. HIGH-risk ZAP alerts fail the pipeline; lower-risk alerts remain in the JSON and HTML reports for triage.

### Stage 7 - Push to Azure Container Registry

This stage should run only after all previous stages pass.

Required CircleCI environment variables:

```text
ACR_LOGIN_SERVER
ACR_USERNAME
ACR_PASSWORD
```

Login:

```bash
echo "$ACR_PASSWORD" | docker login "$ACR_LOGIN_SERVER" \
  -u "$ACR_USERNAME" \
  --password-stdin
```

Build and push with ACR prefix:

```bash
export IMAGE_TAG=${CIRCLE_SHA1}
export IMAGE_REPOSITORY_PREFIX="$ACR_LOGIN_SERVER"

docker compose push
```

The publish operation runs in the same CircleCI machine job as build, Trivy, Compose and ZAP, so it pushes the already-qualified local images without rebuilding them.

Expected ACR image names:

```text
$ACR_LOGIN_SERVER/config-server:<commit_sha>
$ACR_LOGIN_SERVER/discovery-service:<commit_sha>
$ACR_LOGIN_SERVER/gateway:<commit_sha>
$ACR_LOGIN_SERVER/games-service:<commit_sha>
$ACR_LOGIN_SERVER/library-service:<commit_sha>
$ACR_LOGIN_SERVER/order-service:<commit_sha>
$ACR_LOGIN_SERVER/payment-service:<commit_sha>
$ACR_LOGIN_SERVER/user-service:<commit_sha>
$ACR_LOGIN_SERVER/client:<commit_sha>
```

## CircleCI Secrets

Never store secrets in `.circleci/config.yml`.

Use CircleCI environment variables or contexts:

```text
SONAR_TOKEN
SONAR_HOST_URL
ACR_LOGIN_SERVER
ACR_USERNAME
ACR_PASSWORD
IMAGE_REPOSITORY_PREFIX
```

## Current Pipeline Boundaries

Image signing and Kubernetes deployment are intentionally not configured yet. They require a defined Azure target and a least-privilege OIDC identity; they must not be simulated with long-lived credentials in the repository.

Before enabling a release on `master`, configure the restricted CircleCI contexts, ensure SonarQube is reachable from CircleCI, and resolve the blocking HIGH/CRITICAL Trivy findings in the tracked IaC. The pipeline deliberately fails while those findings remain.
