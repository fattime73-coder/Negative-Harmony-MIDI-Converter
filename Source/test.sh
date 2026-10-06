#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/module-cache Examples
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/build/module-cache" Sources/NegativeHarmony/MIDI.swift Sources/NegativeHarmony/Harmony.swift Tests/main.swift -o build/core-tests
build/core-tests "$PWD/Examples"
