.PHONY: setup generate open

setup:
	brew install xcodegen
	$(MAKE) generate

generate:
	xcodegen generate

open:
	open GoogleTask.xcodeproj
