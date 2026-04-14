BINARY := .build/release/providence-overlay
INSTALL_DIR := $(HOME)/.providence/bin

.PHONY: build install clean test

build:
	swift build -c release
	codesign --force --deep --sign - $(BINARY) --entitlements Providence.entitlements
	@echo "Built $(BINARY)"

install: build
	mkdir -p $(INSTALL_DIR)
	cp $(BINARY) $(INSTALL_DIR)/
	@echo "Installed to $(INSTALL_DIR)/providence-overlay"

test:
	swift test

clean:
	swift package clean
	rm -rf .build
