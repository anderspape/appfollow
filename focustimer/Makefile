SHELL := /bin/bash

PERIPHERY_DIR := .tools/periphery
PERIPHERY_REPO := https://github.com/peripheryapp/periphery.git
PERIPHERY_REF := 3a9dd19d0fefc2299cdd8d9ba2358a4e02254dec
PERIPHERY_CONFIG := .periphery.yml
PERIPHERY_BASELINE := .periphery-baseline.json

.PHONY: periphery-install dead-code dead-code-update-baseline

periphery-install:
	@set -euo pipefail; \
	if [[ ! -d "$(PERIPHERY_DIR)/.git" ]]; then \
		mkdir -p "$(PERIPHERY_DIR)"; \
		git clone "$(PERIPHERY_REPO)" "$(PERIPHERY_DIR)"; \
	fi; \
	git -C "$(PERIPHERY_DIR)" fetch --depth 1 origin "$(PERIPHERY_REF)"; \
	git -C "$(PERIPHERY_DIR)" checkout --force "$(PERIPHERY_REF)"; \
	swift build -c release --product periphery --package-path "$(PERIPHERY_DIR)"

dead-code: periphery-install
	@set -euo pipefail; \
	bin_path="$$(swift build -c release --product periphery --package-path "$(PERIPHERY_DIR)" --show-bin-path)"; \
	"$$bin_path/periphery" scan --config "$(PERIPHERY_CONFIG)" --baseline "$(PERIPHERY_BASELINE)" --strict

dead-code-update-baseline: periphery-install
	@set -euo pipefail; \
	bin_path="$$(swift build -c release --product periphery --package-path "$(PERIPHERY_DIR)" --show-bin-path)"; \
	"$$bin_path/periphery" scan --config "$(PERIPHERY_CONFIG)" --write-baseline "$(PERIPHERY_BASELINE)"
