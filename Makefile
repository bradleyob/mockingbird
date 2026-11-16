# MockingBird build tasks.
# Requires Swift 6.2+ (the pinned swift-nio / swift-log need it). Xcode is optional:
# on macOS the Command Line Tools are enough, because tests go through scripts/test.sh.
# Linux targets need Docker (scripts/linux.sh runs the swift:6.2 image).

.DEFAULT_GOAL := help
.PHONY: build build-release test test-core test-cli test-server test-miniaudio test-app \
        linux-build linux-test app run-app deps clean help

build: ## Build every target (debug)
	swift build

build-release: ## Build every target (release)
	swift build -c release

test: ## Run all tests (Swift Testing, via scripts/test.sh)
	./scripts/test.sh

test-core: ## Run MockingBirdCore tests
	./scripts/test.sh --filter MockingBirdCoreTests

test-cli: ## Run mockingbird CLI tests
	./scripts/test.sh --filter MockingBirdCLITests

test-server: ## Run mockingbird-server tests
	./scripts/test.sh --filter MockingBirdServerTests

test-miniaudio: ## Run miniaudio source tests
	./scripts/test.sh --filter MockingBirdMiniAudioTests

test-app: ## Run macOS app view-model tests
	./scripts/test.sh --filter MockingBirdAppTests

linux-build: ## Build on Linux in Docker (swift:6.2)
	./scripts/linux.sh build

linux-test: ## Run tests on Linux in Docker (swift:6.2)
	./scripts/linux.sh test

app: ## Build the ad-hoc-signed build/MockingBird.app
	./scripts/bundle-app.sh

run-app: ## Open build/MockingBird.app (run `make app` first)
	open build/MockingBird.app

deps: ## Resolve package dependencies (honours Package.resolved)
	swift package resolve

clean: ## Remove .build/ and build/
	swift package clean
	rm -rf .build build

help: ## List targets
	@echo "MockingBird make targets:"
	@grep -E '^[a-z][a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN { FS = ":.*## " } { printf "  make %-16s %s\n", $$1, $$2 }'
