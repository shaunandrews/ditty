APP_NAME = Ditty
APP_DIR = $(APP_NAME).app
BUNDLE = $(APP_DIR)/Contents
BUILD_DIR = .build/release

.PHONY: build install clean run

build:
	swift build -c release

install: build
	mkdir -p "$(BUNDLE)/MacOS" "$(BUNDLE)/Resources"
	cp $(BUILD_DIR)/Ditty "$(BUNDLE)/MacOS/"
	cp Info.plist "$(BUNDLE)/"
	xcrun actool Sources/Ditty/Resources/Assets.xcassets \
		--compile "$(BUNDLE)/Resources" \
		--platform macosx \
		--minimum-deployment-target 14.0 \
		--app-icon AppIcon \
		--output-partial-info-plist /dev/null
	codesign --force --sign "DittyDev" --entitlements entitlements.plist "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

run: install
	open "$(APP_DIR)"

clean:
	swift package clean
	rm -rf "$(APP_DIR)"
