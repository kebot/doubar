.PHONY: install dev clean

dev:
	@if [ -n "$$TMUX" ] || [ -n "$$ZELLIJ" ]; then echo "Error: do not run 'make dev' inside tmux/zellij — Tauri needs a native macOS terminal session."; exit 1; fi
	bun tauri dev

install:
	bun install

clean:
	rm -rf dist/ src-tauri/target/

