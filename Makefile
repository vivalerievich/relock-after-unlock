APP := build/RelockAfterUnlock.app
CONTENTS := $(APP)/Contents
BINARY := $(CONTENTS)/MacOS/RelockAfterUnlock

.DELETE_ON_ERROR:
.PHONY: build install uninstall

build: $(BINARY)

$(BINARY): Sources/RelockAfterUnlock.swift Resources/Info.plist $(wildcard Resources/*.lproj/*) Makefile
	/usr/bin/install -d "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	/bin/cp Resources/Info.plist "$(CONTENTS)/Info.plist"
	/bin/cp -R Resources/*.lproj "$(CONTENTS)/Resources/"
	/usr/bin/xcrun swiftc -module-cache-path build/module-cache -swift-version 5 -O -target arm64-apple-macosx27.0 "$<" -o "$@"
	/usr/bin/codesign --force --sign - "$(APP)"

install:
	/bin/sh scripts/launch-agent.sh install

uninstall:
	/bin/sh scripts/launch-agent.sh uninstall
