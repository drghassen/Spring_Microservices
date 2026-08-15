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

The `backend-build-test`, `backend-sonar` and `frontend-sonar` jobs run on the `drghassen/sonar-vm` CircleCI machine runner, installed on the VM that hosts the local SonarQube container. The CircleCI `sonarqube` context must therefore define `SONAR_HOST_URL=http://127.0.0.1:9000`, `SONAR_TOKEN`, and the restricted `SONAR_FRONTEND_TOKEN`.

It keeps the responsibilities separated:

- independent backend and frontend build/test jobs, followed by independent SonarQube quality gates;
- Trivy source-secret, Dockerfile-misconfiguration and image scans that block on HIGH/CRITICAL findings;
- CycloneDX SBOM generation for every application image;
- separate Trivy, container-integration and OWASP ZAP gates, all using the same immutable image archives;
- immutable full-SHA image push to Azure Container Registry only after all gates pass on `master`.

## Recommended CircleCI Pipeline

Professional pipeline order:

```text
backend_build_and_test ────────┐
frontend_build_and_test ───────┴─> backend_sonar_quality_gate ──┐
                                      frontend_sonar_quality_gate ─┤
trivy_source_secrets_and_dockerfiles ────────────────────────────┤
                                                                   ↓
                                      frontend_image_build ───────┐
                                      backend_image_build ────────┴─> image_trivy_scan
                                                                            ↓
                                                                  container_integration
                                                                            ↓
                                                                        OWASP_ZAP_DAST
                                                                            ↓
                                                               push_approved_SHA_images_to_ACR
```

The backend and frontend builds run in parallel. Once both succeed, their two SonarQube quality gates run in parallel; the independent source scan is an additional early gate. The frontend and backend Docker images are then built in separate parallel jobs. Non-`master` branches run the full container qualification with local `ci.local` image tags. `master` pushes only images that pass every gate.

The SonarQube workspace transfers only JaCoCo XML plus compiled backend classes in `ci-backend-sonar/`, and the Angular LCOV file in `ci-frontend-sonar/`. To enforce independently visible image, integration and DAST jobs, the image-build jobs export two zstd-compressed Docker archives with SHA-256 checksums in `ci-image-archives/`. Each downstream job verifies and loads those exact archives; images are never rebuilt after Trivy.

### Stage 1 - Backend Build, Tests and Coverage

```bash
mvn -B -ntp clean verify
```

It stages only compiled classes and JaCoCo XML for the later backend SonarQube job.

### Stage 2 - Frontend Tests and Build

```bash
cd UI_Spring
npm ci
npm run test -- --watch=false --browsers=ChromeHeadless
npm run build -- --configuration=production
```

### Stage 3 - Parallel SonarQube Quality Gates

The backend gate restores the staged backend artifacts, and the frontend gate restores the LCOV report. Both wait for their respective SonarQube quality gate before the image stage is allowed to start.

### Stage 4 - Trivy Filesystem Scan

Blocking mode:

```bash
trivy fs \
  --scanners secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  --timeout 20m \
  .
```

### Stage 5 - Parallel Docker Image Builds

```bash
export IMAGE_TAG=${CIRCLE_SHA1}
export IMAGE_REPOSITORY_PREFIX=ghassen_dridi

docker compose build client
docker compose build config-server discovery-service gateway games-service library-service \
  order-service payment-service user-service
```

The two jobs export the image groups as compressed archives, allowing all subsequent independent jobs to use the same image digests.

### Stage 6 - SBOM and Trivy Image Scan

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

### Stage 7 - Docker Compose and Eureka Integration

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

The CI waits until Eureka reports exactly one instance for each expected application. Compose logs are retained as artifacts and the test stack is removed.

### Stage 8 - OWASP ZAP DAST

The DAST job reloads the same archives and starts a clean test stack. It runs passive ZAP baseline scans against the client and gateway, then active ZAP API scans against the five OpenAPI contracts routed by the gateway (`users`, `games`, `library`, `order`, and `payment`). HIGH-risk ZAP alerts fail the pipeline; lower-risk alerts remain in the JSON and HTML reports for triage. The active API scans run only against disposable CI data; authenticated-route coverage can be added later with a dedicated test account and ZAP context. A running Docker container cannot be transferred safely from one isolated CircleCI job to another, so DAST starts a new instance of the same qualified image rather than reusing the prior job's container.

### Stage 9 - Push to Azure Container Registry

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

The publishing script retags the already-tested local `ci.local/<service>:<commit_sha>` image to the ACR repository and then pushes it. It never calls `docker compose build` again:

```bash
docker image tag "ci.local/config-server:${CIRCLE_SHA1}" \
  "${ACR_LOGIN_SERVER}/config-server:${CIRCLE_SHA1}"
docker push "${ACR_LOGIN_SERVER}/config-server:${CIRCLE_SHA1}"
```

The publish job reloads the archived images after DAST and pushes them without rebuilding them.

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
```

### Azure Communication Services security-alert context

CircleCI's native **My work** notification is not sufficient for security incidents: it does not send the scanner findings or a report. The pipeline instead sends a real incident e-mail through Azure Communication Services (ACS) when a SonarQube, Trivy, or OWASP ZAP gate fails.

Create a restricted CircleCI context named `security-alerts` and set the following variables there:

```text
AZURE_COMMUNICATION_CONNECTION_STRING=<ACS secondary connection string>
ACS_EMAIL_SENDER=DoNotReply@9afef845-00c2-4039-9964-58b09ec98456.azurecomm.net
SECURITY_ALERT_RECIPIENTS=ghassen.dridi@episousse.com.tn
```

Retrieve the first value locally and paste it directly into CircleCI; never print, commit, or share it:

```bash
az communication list-key \
  --name ghassen-devsecops-acs \
  --resource-group internship_proxym \
  --query secondaryConnectionString \
  --output tsv
```

`send-security-alert.sh` runs with `when: on_fail`. It creates a readable `.txt` summary containing the failing scanner, commit, branch, CircleCI job URL, and HIGH/CRITICAL findings. It e-mails that summary through ACS and attaches it as a text report. The complete JSON/HTML scanner reports remain in CircleCI artifacts. If ACS delivery fails, the script exits successfully so it cannot hide or replace the original blocking scanner failure.

The current ACS resources are `ghassen-devsecops-email` (Email Communication Service), its Azure-managed domain, and `ghassen-devsecops-acs` (Communication Service), all in `internship_proxym` with `Europe` data location. The Azure-managed sender is suitable for CI alerts; use a verified company domain later if a branded sender address is required.

## Current Pipeline Boundaries

Image signing and Kubernetes deployment are intentionally not configured yet. The next production hardening step is Azure workload-identity federation (OIDC) for CircleCI, replacing the long-lived `ACR_USERNAME` and `ACR_PASSWORD`, then signing the pushed image digests with Cosign before deployment. They require a defined Azure target and a least-privilege identity; they must not be simulated with credentials in the repository.

Before enabling a release on `master`, configure the restricted CircleCI contexts, ensure SonarQube is reachable from CircleCI, and resolve the blocking HIGH/CRITICAL Trivy findings in the tracked IaC. The pipeline deliberately fails while those findings remain.
