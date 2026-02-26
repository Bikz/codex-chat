SHELL := /bin/bash

.PHONY: quick ci format format-check lint test-fast test periphery release-dmg release-prod release-next-version release-tag-next host-metadata-check parity-check oss-smoke reliability-local reliability-scorecard reliability-bundle remote-control-load remote-control-soak remote-control-gate remote-control-load-gated remote-control-gke-validate remote-control-stage-gate prepush-local install-local-hooks bootstrap

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

reliability-local:
	./scripts/runtime-reliability-local.sh

reliability-scorecard:
	./scripts/runtime-reliability-scorecard.sh

reliability-bundle:
	./scripts/runtime-reliability-bundle.sh

remote-control-load:
	./scripts/remote-control-relay-load.sh

remote-control-soak:
	./scripts/remote-control-relay-soak.sh

remote-control-gate:
	./scripts/remote-control-relay-gate.sh

remote-control-load-gated: remote-control-load remote-control-gate

remote-control-gke-validate:
	./scripts/remote-control-relay-gke-validate.sh

remote-control-stage-gate:
	./scripts/remote-control-stage-gate.sh

prepush-local: quick oss-smoke reliability-local

install-local-hooks:
	./scripts/install-local-git-hooks.sh

bootstrap:
	./scripts/bootstrap.sh
