.PHONY: install dev build bundle clean link

dev:
	@if [ -n "$$TMUX" ] || [ -n "$$ZELLIJ" ]; then echo "Error: do not run 'make dev' inside tmux/zellij — Tauri needs a native macOS terminal session."; exit 1; fi
	@./scripts/dev.sh

build:
	bun tauri build --target aarch64-apple-darwin --no-bundle

# link the binary to $PATH
link: build
	@mkdir -p "$(HOME)/.local/bin"
	ln -sf "$(PWD)/src-tauri/target/aarch64-apple-darwin/release/doubar" "$(HOME)/.local/bin/doubar"

# build the full .app + .dmg if needed (currenctly have permission issues)
bundle:
	bun tauri build --target aarch64-apple-darwin

install:
	bun install

clean:
	rm -rf dist/ src-tauri/target/

