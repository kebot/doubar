.PHONY: install dev clean

dev:
	bun tauri dev

install:
	bun install

clean:
	rm -rf dist/ src-tauri/target/

