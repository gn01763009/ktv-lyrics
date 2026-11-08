.PHONY: test app coverage install release

APP_NAME := KTV Lyrics.app
BUILT_APP := build/$(APP_NAME)
INSTALLED_APP := /Applications/$(APP_NAME)
RELEASE_ZIP := build/KTV-Lyrics.zip

test:
	swift test

app:
	scripts/build-app.sh

coverage:
	scripts/check-coverage.sh

# Builds the app, then replaces any previous copy in /Applications.
install: app
	@echo "Removing the previous copy at $(INSTALLED_APP), if there is one"
	rm -rf "$(INSTALLED_APP)"
	@echo "Copying $(BUILT_APP) to $(INSTALLED_APP) with ditto"
	ditto "$(BUILT_APP)" "$(INSTALLED_APP)"
	@echo "Installed $(INSTALLED_APP)"

release: app
	rm -f "$(RELEASE_ZIP)"
	ditto -c -k --keepParent "$(BUILT_APP)" "$(RELEASE_ZIP)"
	@echo "Created $(RELEASE_ZIP)"
