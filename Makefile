PREFIX ?= /usr/local
BINARY_NAME = apfel-chat
APP_NAME = apfel chat
APP_BUNDLE = build/$(APP_NAME).app

.PHONY: build install clean test app app-run

build:
	swift build -c release

test:
	swift test

install: build
	@mkdir -p $(PREFIX)/bin
	@cp .build/release/$(BINARY_NAME) $(PREFIX)/bin/$(BINARY_NAME)
	@echo "Installed $(BINARY_NAME) to $(PREFIX)/bin/$(BINARY_NAME)"

app: build
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp .build/release/$(BINARY_NAME) "$(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	@sed 's/1\.0\.0/1.0.0/g' Info.plist > "$(APP_BUNDLE)/Contents/Info.plist"
	@test -f Resources/AppIcon.icns && cp Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/" || true
	@test -f PrivacyInfo.xcprivacy && cp PrivacyInfo.xcprivacy "$(APP_BUNDLE)/Contents/Resources/" || true
	@echo "Built: $(APP_BUNDLE)"

app-run: app
	@open "$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf .build build
