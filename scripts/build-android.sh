#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
# Gradle selects JDK 21 using gradle/gradle-daemon-jvm.properties.
# Do not use Android Studio's bundled runtime: IDE updates can change its major version.
./gradlew :app:assembleDebug "$@"
mkdir -p output
cp app/build/outputs/apk/debug/app-debug.apk output/AbyssRelay-debug.apk
printf 'Android APK: %s/output/AbyssRelay-debug.apk\n' "$ROOT_DIR"
