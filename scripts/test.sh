#!/usr/bin/env bash
# Xcode 없이 Command Line Tools만 있어도 Swift Testing이 돌도록 프레임워크 경로를 넘긴다.
set -euo pipefail
cd "$(dirname "$0")/.."
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
if [ -d "$FW/Testing.framework" ]; then
  swift test -Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" "$@"
else
  swift test "$@"
fi
