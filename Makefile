APP_NAME := Providence Overlay
BUNDLE_ID := com.gravitrone.providence.overlay

BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/providence-overlay
APP := build/Providence Overlay.app
APP_MACOS := $(APP)/Contents/MacOS
APP_RESOURCES := $(APP)/Contents/Resources
APP_PLIST := $(APP)/Contents/Info.plist

INSTALL_APPS_DIR := $(HOME)/Applications
INSTALL_BIN_DIR := $(HOME)/.providence/bin
INSTALLED_APP := $(INSTALL_APPS_DIR)/Providence Overlay.app
INSTALLED_SHIM := $(INSTALL_BIN_DIR)/providence-overlay

.PHONY: build app install clean test version

build:
	swift build -c release

# Wrap the compiled binary in a .app bundle
app: build
	@echo "Building .app bundle at $(APP)..."
	rm -rf "$(APP)"
	mkdir -p "$(APP_MACOS)"
	mkdir -p "$(APP_RESOURCES)"
	cp "$(BINARY)" "$(APP_MACOS)/"
	cp Info.plist "$(APP_PLIST)"
	# Sign the .app bundle (not just the binary) so TCC tracks bundle identity
	codesign --force --deep --sign - --entitlements Providence.entitlements "$(APP)"
	@echo "Verifying signature..."
	codesign --verify --verbose=2 "$(APP)"
	@echo "Bundle ID: $$(defaults read "$$PWD/$(APP)/Contents/Info.plist" CFBundleIdentifier)"

install: app
	@mkdir -p "$(INSTALL_APPS_DIR)"
	@mkdir -p "$(INSTALL_BIN_DIR)"
	# Copy the .app to ~/Applications (stable location, not System-protected)
	rsync -a --delete "$(APP)/" "$(INSTALLED_APP)/"
	# Install a shim script at ~/.providence/bin/providence-overlay that exec's the .app binary
	@echo "Creating shim at $(INSTALLED_SHIM)..."
	@echo '#!/bin/sh' > "$(INSTALLED_SHIM)"
	@echo 'exec "$$HOME/Applications/Providence Overlay.app/Contents/MacOS/providence-overlay" "$$@"' >> "$(INSTALLED_SHIM)"
	chmod +x "$(INSTALLED_SHIM)"
	@echo "Installed:"
	@echo "  .app  -> $(INSTALLED_APP)"
	@echo "  shim  -> $(INSTALLED_SHIM)"
	@echo ""
	@echo "TCC bundle identity: $(BUNDLE_ID)"
	@echo "Reset with: tccutil reset ScreenCapture $(BUNDLE_ID)"

test:
	swift test

version:
	@defaults read "$$PWD/$(APP)/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "not built"

clean:
	swift package clean
	rm -rf .build build
