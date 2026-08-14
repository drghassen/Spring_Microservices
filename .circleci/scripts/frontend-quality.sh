#!/usr/bin/env bash

set -euo pipefail

npm ci --prefix UI_Spring
npm run test --prefix UI_Spring -- --watch=false --browsers=ChromeHeadless
npm run build --prefix UI_Spring -- --configuration=production
