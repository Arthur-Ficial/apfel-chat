APP_NAME    = apfel-chat
APP_BUNDLE  = build/$(APP_NAME).app
APP_DIR    ?= /Applications
BIN_DIR    ?= $(HOME)/.local/bin

.PHONY: build test app run dist install install-app install-cli release clean

build:
	swift build -c release

test:
	swift test

app:
	./scripts/build-app.sh

run: app
	open "$(APP_BUNDLE)"

dist:
	./scripts/build-dist.sh

release:
	./scripts/release.sh

install: install-app

install-app: app
	@if [ -w "$(APP_DIR)" ]; then \
		rm -rf "$(APP_DIR)/$(APP_NAME).app"; \
		ditto "$(APP_BUNDLE)" "$(APP_DIR)/$(APP_NAME).app"; \
	else \
		sudo rm -rf "$(APP_DIR)/$(APP_NAME).app"; \
		sudo ditto "$(APP_BUNDLE)" "$(APP_DIR)/$(APP_NAME).app"; \
	fi
	@echo "Installed $(APP_NAME).app to $(APP_DIR)"

install-cli: install-app
	@mkdir -p "$(BIN_DIR)"
	@ln -sf "$(APP_DIR)/$(APP_NAME).app/Contents/MacOS/$(APP_NAME)" "$(BIN_DIR)/$(APP_NAME)"
	@echo "Linked $(APP_NAME) into $(BIN_DIR)"

clean:
	swift package clean
	rm -rf .build build dist
