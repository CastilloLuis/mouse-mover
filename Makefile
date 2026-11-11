APP_NAME   := MouseMover
BUNDLE_ID  := local.MouseMover
CONFIG     ?= release
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
# "-" is an ad-hoc signature. Set SIGN_ID to a real identity (see
# `security find-identity -v -p codesigning`) to keep the Accessibility
# grant across rebuilds.
SIGN_ID    ?= -

.PHONY: build run stop clean

## build: compile and assemble an ad-hoc signed build/MouseMover.app
build:
	swift build -c $(CONFIG) --arch arm64
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c $(CONFIG) --arch arm64 --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_ID)" "$(APP)"
	codesign --verify --verbose=1 "$(APP)"

## run: build, then open the app (it shows in the menu bar only)
run: build
	open "$(APP)"

## stop: quit the running app the normal way
stop:
	osascript -e 'tell application id "$(BUNDLE_ID)" to quit'

## clean: remove build output
clean:
	rm -rf .build "$(BUILD_DIR)"
