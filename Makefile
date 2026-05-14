# MockingBird build scripts
# Requires: swift 6+, Xcode 16+ (macOS), or Swift toolchain (Linux)

.PHONY: build build-release test test-all clean lint help

# ── Build ────────────────────────────────────────────────────────────────────

## Build all targets (debug)
build:
	swift build

## Build MockingBirdCore library only
build-core:
	swift build --target MockingBirdCore

## Build the mockingbird CLI binary (debug)
build-cli:
	swift build --target MockingBirdCLI

## Build the mockingbird-server binary (debug)
build-server:
	swift build --target MockingBirdServer

## Build all targets in release mode
build-release:
	swift build -c release

## Build release CLI binary and print its path
build-cli-release:
	swift build -c release --target MockingBirdCLI
	@echo "Binary: $$(swift build -c release --target MockingBirdCLI --show-bin-path)/mockingbird"

# ── Test ─────────────────────────────────────────────────────────────────────

## Run MockingBirdCore unit + integration tests
test:
	swift test --filter MockingBirdCoreTests

## Run all tests
test-all:
	swift test

## Run tests with verbose output
test-verbose:
	swift test --filter MockingBirdCoreTests --verbose

# ── Maintenance ───────────────────────────────────────────────────────────────

## Remove build artifacts
clean:
	swift package clean
	rm -rf .build

## Resolve/update package dependencies
deps:
	swift package resolve

## Update all dependencies to latest compatible versions
deps-update:
	swift package update

# ── Help ─────────────────────────────────────────────────────────────────────

## Print this help message
help:
	@echo "MockingBird — available targets:"
	@echo ""
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## /  /'
	@echo ""
	@grep -E '^[a-z][a-zA-Z_-]+:' $(MAKEFILE_LIST) | sed 's/:.*//' | \
		awk '{printf "  make %-20s\n", $$1}'
