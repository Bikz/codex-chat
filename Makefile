SHELL := /bin/bash

.PHONY: quick ci format format-check lint test-fast test periphery release-dmg host-metadata-check parity-check

quick: host-metadata-check parity-check format-check lint test-fast

ci: host-metadata-check parity-check format-check lint test

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

host-metadata-check:
	./scripts/check-host-app-metadata.sh

parity-check:
	./scripts/verify-build-settings-parity.sh
