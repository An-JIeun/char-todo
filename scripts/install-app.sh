#!/usr/bin/env bash
# 릴리스 빌드 → /Applications/CharTodo.app 설치 → 실행
# 설치 후에는 Launchpad · Spotlight(⌘Space) · Dock 아이콘으로 바로 실행된다. 코드를 고친 뒤 다시 돌리면 업데이트.
# 사용: ./scripts/install-app.sh            (설치 후 실행)
#       ./scripts/install-app.sh --no-open  (설치만)
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="/Applications/CharTodo.app"

# 실행 중이면 먼저 종료 (할일·회의록은 Application Support에 있어 그대로 남는다)
if pgrep -xq CharTodo; then
  echo "▶ 실행 중인 CharTodo 종료"
  osascript -e 'quit app "CharTodo"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -xq CharTodo || break; sleep 0.5; done
fi

./scripts/build-app.sh release

echo "▶ $DEST 설치"
rm -rf "$DEST"
cp -R build/CharTodo.app "$DEST"
# Launchpad · Spotlight · chartodo:// 링크가 새 앱을 가리키도록 등록
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" >/dev/null 2>&1 || true

echo "✅ 설치 완료 — Launchpad · Spotlight(⌘Space → CharTodo) · Dock 에서 실행하세요"
if [ "${1:-}" != "--no-open" ]; then open "$DEST"; fi
