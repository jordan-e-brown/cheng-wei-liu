#!/usr/bin/env bash
set -euo pipefail

echo "成为流 — VS Code / Intel Mac setup"
echo

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "Note: this setup was optimized for an Intel Mac; detected $(uname -m)."
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Full Xcode is not selected. Install Xcode 26.6, then run:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  sudo xcodebuild -runFirstLaunch
MSG
  exit 1
fi

sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required for the streamlined setup: https://brew.sh" >&2
  exit 1
fi

brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

if command -v code >/dev/null 2>&1; then
  code --install-extension swiftlang.swift-vscode --force || true
  code --install-extension ms-python.python --force || true
else
  echo "VS Code's 'code' command is not on PATH."
  echo "In VS Code: Command Palette → Shell Command: Install 'code' command in PATH"
fi

xcodegen generate

echo
echo "Setup complete."
echo "Run 'make doctor' and then 'make build-sim'."
echo "For the Intel-compatible simulator runtime, run 'make simulator-runtime' only if you need Simulator testing."
