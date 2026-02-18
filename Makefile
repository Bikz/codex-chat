SHELL := /bin/bash

.PHONY: quick ci format format-check lint test-fast test periphery release-dmg

quick: format-check lint test-fast

ci: format-check lint test

format:
	./scripts/swiftformat.sh

format-check:
	./scripts/swiftformat-check.sh

lint:
	./scripts/swiftlint.sh

test-fast:
	./scripts/swift-test-fast.sh

test:
	pnpm -s run check

periphery:
	./scripts/periphery-scan.sh

release-dmg:
	./scripts/release/build-notarized-dmg.sh
