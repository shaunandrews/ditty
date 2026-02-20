APP_NAME = Music Controller
APP_DIR = $(APP_NAME).app
BUNDLE = $(APP_DIR)/Contents
BUILD_DIR = .build/release

.PHONY: build install clean run

build:
	swift build -c release

install: build
	mkdir -p "$(BUNDLE)/MacOS"
	cp $(BUILD_DIR)/MusicController "$(BUNDLE)/MacOS/"
	cp Info.plist "$(BUNDLE)/"
	codesign --force --sign - --entitlements entitlements.plist "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

run: install
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf "$(APP_DIR)"
