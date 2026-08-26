#!/usr/bin/env bash
set -u
fail=0

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf "✓ %s\n" "$name"
  else
    printf "✗ %s\n" "$name"
    fail=1
  fi
}

echo "成为流 development environment"
echo "---------------------------"
printf "macOS: %s\n" "$(sw_vers -productVersion 2>/dev/null || echo unknown)"
printf "Architecture: %s\n" "$(uname -m)"
check "Full Xcode toolchain selected" xcodebuild -version
check "xcodegen" xcodegen --version
check "Swift" swift --version
check "Python 3" python3 --version
check "Git" git --version

if command -v xcodebuild >/dev/null 2>&1; then
  echo
  xcodebuild -version || true
  echo
  echo "Selected developer directory:"
  xcode-select -p || true
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Run ./scripts/setup_vscode_intel.sh for the missing pieces."
  exit 1
fi
