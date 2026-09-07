SHELL := /bin/bash
PROJECT := ChengWeiLiu.xcodeproj
SCHEME := ChengWeiLiu
DERIVED ?= /tmp/ChengWeiLiuDerivedData
TEAM_ID ?=
DEVICE_ID ?=

.PHONY: doctor setup generate simulator-runtime build-sim build-device clean backend backend-lan backend-install test-backend list-sims list-devices

doctor:
	./scripts/doctor.sh

setup:
	./scripts/setup_vscode_intel.sh

generate:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen: brew install xcodegen" && exit 1)
	xcodegen generate

simulator-runtime:
	xcodebuild -downloadPlatform iOS -architectureVariant universal

build-sim: generate
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-sdk iphonesimulator \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES \
		build

build-device: generate
	@test -n "$(TEAM_ID)" || (echo "Usage: make build-device TEAM_ID=YOUR_APPLE_TEAM_ID" && exit 1)
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-sdk iphoneos \
		-destination 'generic/platform=iOS' \
		-derivedDataPath $(DERIVED) \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		-allowProvisioningUpdates \
		build

list-sims:
	xcrun simctl list devices available

list-devices:
	xcrun devicectl list devices

clean:
	rm -rf $(DERIVED) $(PROJECT)

backend-install:
	cd Backend && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

backend:
	@if [ ! -x Backend/.venv/bin/uvicorn ]; then $(MAKE) backend-install; fi
	cd Backend && .venv/bin/uvicorn app.main:app --reload --host 127.0.0.1 --port 8000

backend-lan:
	./scripts/run_backend_lan.sh

test-backend:
	@if [ ! -x Backend/.venv/bin/python ]; then $(MAKE) backend-install; fi
	cd Backend && .venv/bin/python -m unittest discover -s tests -v

.PHONY: test-anki test-ios build-device-unsigned

test-anki:
	PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tools/AnkiExporter/tests -v

test-ios: generate
	@test -n "$(DEVICE_ID)" || (echo "Usage: make test-ios DEVICE_ID=SIMULATOR_UDID" && exit 1)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-destination 'platform=iOS Simulator,id=$(DEVICE_ID)' -derivedDataPath $(DERIVED) \
		-parallel-testing-enabled NO CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test

build-device-unsigned: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath $(DERIVED) \
		CODE_SIGNING_ALLOWED=NO build
