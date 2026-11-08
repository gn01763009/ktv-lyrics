.PHONY: test app

test:
	swift test

app:
	scripts/build-app.sh
