#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/snake-native-checks.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -module-cache-path "$test_dir/modules" ios/SnakeClash/GameWorld.swift ios/SnakeClash/SoundSynthesis.swift test/native/main.swift -o "$test_dir/checks"
"$test_dir/checks"
