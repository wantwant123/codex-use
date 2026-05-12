#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

CMD="${1:-app}"

usage() {
  cat <<'EOF'
Usage:
  ./build.sh app          Build unsigned Release .app (default)
  ./build.sh dmg          Build unsigned universal .dmg
  ./build.sh open [lang]  Build Release .app and open it, optional lang: zh-Hans / en
  ./build.sh run          Build Debug .app and open it
  ./build.sh logs         Build Debug .app, open it, and follow logs
  ./build.sh test         Run macOS tests

Requirements:
  - Full Xcode, not Command Line Tools only
  - create-dmg for ./build.sh dmg: brew install create-dmg
EOF
}

require_xcodebuild() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "error: xcodebuild not found. Install full Xcode and run:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi

  if ! xcodebuild -version >/dev/null 2>&1; then
    echo "error: xcodebuild is not usable. This usually means xcode-select points to Command Line Tools." >&2
    echo "Fix with:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
  fi
}

prepare_sources() {
  make l10n
}

case "$CMD" in
  app|build)
    require_xcodebuild
    prepare_sources
    script/release_build.sh build
    ;;
  dmg)
    require_xcodebuild
    prepare_sources
    script/release_build.sh dmg
    ;;
  open)
    require_xcodebuild
    prepare_sources
    shift
    script/release_build.sh open "$@"
    ;;
  run)
    require_xcodebuild
    prepare_sources
    script/build_and_run.sh run
    ;;
  logs)
    require_xcodebuild
    prepare_sources
    script/build_and_run.sh logs
    ;;
  test)
    require_xcodebuild
    prepare_sources
    xcodebuild test \
      -project agent-battery.xcodeproj \
      -scheme agent-battery \
      -destination 'platform=macOS'
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
