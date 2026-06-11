APP_NAME = Holler
APP_DIR = build/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)

.PHONY: all build app install uninstall run dist clean

all: app

# SWIFT_FLAGS=--disable-sandbox is passed by the Homebrew formula: SwiftPM's own
# build sandbox cannot nest inside brew's sandbox.
SWIFT_FLAGS ?=

build:
	swift build -c release $(SWIFT_FLAGS)

app: build
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS $(APP_DIR)/Contents/Resources
	cp $(BINARY) $(APP_DIR)/Contents/MacOS/$(APP_NAME)
	cp Support/Info.plist $(APP_DIR)/Contents/Info.plist
	codesign --force --sign - $(APP_DIR)
	@echo "Built $(APP_DIR)"

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/
	@echo "Installed. Launch with: open /Applications/$(APP_NAME).app"

uninstall:
	rm -rf /Applications/$(APP_NAME).app

run: app
	open $(APP_DIR)

dist: app
	cd build && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME)-$(VERSION).zip
	@echo "Built build/$(APP_NAME)-$(VERSION).zip"

clean:
	rm -rf build .build
