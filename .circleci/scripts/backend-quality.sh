#!/usr/bin/env bash

set -euo pipefail

mvn -B -ntp clean verify

: "${SONAR_HOST_URL:?SONAR_HOST_URL must be defined in the sonarqube CircleCI context}"
: "${SONAR_TOKEN:?SONAR_TOKEN must be defined in the sonarqube CircleCI context}"

mvn -B -ntp \
  org.sonarsource.scanner.maven:sonar-maven-plugin:sonar \
  -Dsonar.projectKey=Internship-Proxym \
  -Dsonar.projectName='Internship Proxym' \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300
