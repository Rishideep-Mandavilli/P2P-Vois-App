#!/bin/zsh
# Build the release APK with a versioned filename in dist/.
# Bump pubspec version +1 before running for a new build.
set -e
cd "$(dirname "$0")/.."
VERSION=$(grep '^version:' pubspec.yaml | awk '{print $2}')
flutter build apk --release > /dev/null
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "dist/vois-v${VERSION}.apk"
echo "Built dist/vois-v${VERSION}.apk"
