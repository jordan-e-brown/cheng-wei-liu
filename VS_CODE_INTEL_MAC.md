# VS Code workflow — Intel Mac

This repository is designed so the Xcode **IDE** is optional. Xcode 26.6 stays installed because Apple's compiler, iOS SDK, signing, `xcodebuild`, WidgetKit tooling, Simulator, and device tools come from it.

## Current baseline

- Intel Mac (`x86_64`)
- macOS 26.2+
- Xcode 26.6
- iPhone iOS 26.6.1
- VS Code

## First setup

```bash
./scripts/setup_vscode_intel.sh
make doctor
code .
```

The setup installs XcodeGen through Homebrew if needed and generates `ChengWeiLiu.xcodeproj`.

## Routine commands

```bash
make generate
make build-sim
make test-backend
make backend-lan
make list-devices
```

`Cmd+Shift+B` in VS Code invokes the default simulator build task.

## Intel Simulator runtime

Do not download another simulator runtime unless you actually need Simulator testing. For Intel compatibility:

```bash
make simulator-runtime
```

This requests Apple's universal iOS runtime.

## Physical iPhone

For this app, the physical iPhone is the more important validation target because WidgetKit refresh timing, App Groups, local-network permissions, and later realtime audio behavior should be tested on-device.

Before signing, edit `Config/Base.xcconfig` and replace the example bundle/App Group identifiers with identifiers you control.
