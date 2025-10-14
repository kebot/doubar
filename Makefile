.PHONY: install dev

install:
	deno install

dev:
	deno task tauri dev
