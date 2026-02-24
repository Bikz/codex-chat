SHELL := /bin/bash

.PHONY: quick ci format format-check lint test-fast test periphery release-dmg release-prod release-next-version release-tag-next host-metadata-check parity-check oss-smoke bootstrap

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

release-prod:
	./scripts/release/release-prod.sh

release-next-version:
	./scripts/release/next-version.sh

release-tag-next:
	./scripts/release/tag-next-release.sh

host-metadata-check:
	./scripts/check-host-app-metadata.sh

parity-check:
	./scripts/verify-build-settings-parity.sh

oss-smoke:
	./scripts/oss-smoke.sh

bootstrap:
	./scripts/bootstrap.sh
