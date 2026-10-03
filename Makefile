.PHONY: dev build bundle link clean

RELEASE := .build/release/doubar
APP := .build/doubar.app

# build and run in the foreground (Ctrl-C to stop)
dev:
	swift run doubar

build:
	swift build -c release --arch arm64

# link the binary to $PATH
link: build
	@mkdir -p "$(HOME)/.local/bin"
	ln -sf "$(PWD)/$(RELEASE)" "$(HOME)/.local/bin/doubar"

# a minimal .app (LSUIElement, ad-hoc signed) for Login Items
bundle: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$(RELEASE)" "$(APP)/Contents/MacOS/doubar"
	cp assets/Info.plist "$(APP)/Contents/Info.plist"
	cp assets/icon.icns "$(APP)/Contents/Resources/icon.icns"
	codesign --force --sign - "$(APP)"

clean:
	rm -rf .build
