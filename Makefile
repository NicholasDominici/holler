APP_NAME = Holler
APP_DIR = build/$(APP_NAME).app
BINARY = .build/release/$(APP_NAME)
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Support/Info.plist)
DMG = build/$(APP_NAME)-$(VERSION).dmg

# Auto-detected Developer ID Application identity (empty until the cert exists).
SIGN_ID := $(shell security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/')
# Keychain profile holding the notarization credentials (see `make notary-setup`).
NOTARY_PROFILE ?= holler-notary

.PHONY: all build app install uninstall run dist sign notarize-app dmg notarize-dmg release verify notary-setup clean

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
	@echo "Built $(APP_DIR) (ad-hoc signed)"

install: app
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_DIR) /Applications/
	@echo "Installed. Launch with: open /Applications/$(APP_NAME).app"

uninstall:
	rm -rf /Applications/$(APP_NAME).app

run: app
	open $(APP_DIR)

# Ad-hoc zip — for technical users who'll click "Open Anyway".
dist: app
	cd build && ditto -c -k --keepParent $(APP_NAME).app $(APP_NAME)-$(VERSION).zip
	@echo "Built build/$(APP_NAME)-$(VERSION).zip"

# ---- Signed + notarized distribution ----

# One-time: store notarization credentials in the keychain. Prompts for the
# app-specific password interactively so it never lands in the shell history.
#   make notary-setup APPLE_ID=you@example.com TEAM_ID=XXXXXXXXXX
notary-setup:
	@test -n "$(APPLE_ID)" || { echo "Set APPLE_ID=you@example.com"; exit 1; }
	@test -n "$(TEAM_ID)" || { echo "Set TEAM_ID=XXXXXXXXXX"; exit 1; }
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
		--apple-id "$(APPLE_ID)" --team-id "$(TEAM_ID)"

# Re-sign the bundle with the Developer ID cert + hardened runtime.
sign: app
	@test -n "$(SIGN_ID)" || { echo "No Developer ID Application certificate found in keychain."; exit 1; }
	codesign --force --deep --options runtime --timestamp \
		--entitlements Support/Holler.entitlements \
		--sign "$(SIGN_ID)" $(APP_DIR)
	codesign --verify --strict --verbose=2 $(APP_DIR)
	@echo "Signed with: $(SIGN_ID)"

# Notarize the app (via a zip), then staple the ticket onto the .app itself so
# it launches offline.
notarize-app: sign
	cd build && ditto -c -k --keepParent $(APP_NAME).app notarize-app.zip
	xcrun notarytool submit build/notarize-app.zip \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(APP_DIR)
	rm -f build/notarize-app.zip

# Build the drag-to-Applications DMG from the stapled app.
dmg: notarize-app
	rm -rf build/dmg $(DMG)
	mkdir -p build/dmg
	cp -R $(APP_DIR) build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg \
		-ov -format UDZO "$(DMG)"
	rm -rf build/dmg
	@echo "Built $(DMG)"

# Notarize and staple the DMG itself, so the download is trusted before mount.
notarize-dmg: dmg
	xcrun notarytool submit "$(DMG)" \
		--keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(DMG)"

# Full release artifact: signed, notarized, stapled DMG.
release: notarize-dmg verify
	@echo ""
	@echo "Release ready: $(DMG)"

verify:
	@echo "=== codesign ==="
	codesign --verify --deep --strict --verbose=2 $(APP_DIR)
	@echo "=== DMG staple ticket ==="
	xcrun stapler validate "$(DMG)"
	@echo "=== Gatekeeper assessment of the app inside the DMG ==="
	@MNT=$$(hdiutil attach "$(DMG)" -nobrowse -readonly | grep Volumes | sed -E 's/.*(\/Volumes\/.*)$$/\1/'); \
	spctl -a -t exec -vvv "$$MNT/$(APP_NAME).app"; \
	STATUS=$$?; \
	hdiutil detach "$$MNT" >/dev/null; \
	exit $$STATUS

clean:
	rm -rf build .build
