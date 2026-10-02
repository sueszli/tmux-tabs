SHELL := /bin/bash
.DEFAULT_GOAL := help

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
SH_FILES := tmux-tabs.sh install.sh update.sh $(wildcard tests/*.sh)
JS_FILES := $(wildcard tests/*.mjs)
SHFMT_FLAGS := -i 4 -ci

.PHONY: help fmt lint syntax tests check precommit precommit-hook

help: ## Show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

# Format Bash sources in place. Install shfmt before running this target.
fmt: ## Format Bash files in place
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	$(SHFMT) $(SHFMT_FLAGS) -w $(SH_FILES)

# Check formatting and shell correctness without changing files.
lint: ## Run ShellCheck and check formatting
	@command -v $(SHELLCHECK) >/dev/null || { echo 'ShellCheck required (see README)' >&2; exit 1; }
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	$(SHELLCHECK) $(SH_FILES)
	$(SHFMT) $(SHFMT_FLAGS) -d $(SH_FILES)

syntax: ## Check Bash and JavaScript syntax
	@for file in $(SH_FILES); do bash -n "$$file" || exit; done
	@for file in $(JS_FILES); do node --check "$$file" || exit; done

tests: ## Run shell tests (requires jq and Node.js)
	@command -v jq >/dev/null || { echo 'jq required' >&2; exit 1; }
	@command -v node >/dev/null || { echo 'Node.js required' >&2; exit 1; }
	@if [ -z "$(wildcard tests/*.sh)" ]; then \
		echo 'No tests/*.sh scripts found' >&2; exit 1; \
	fi
	@set -e; for file in $(wildcard tests/*.sh); do bash "$$file"; done

check: syntax lint tests ## Run all checks without modifying files

# Like exojit's precommit: format first, then run all checks.
# Recursive make keeps formatting ahead of checks even with make -j.
precommit: ## Format files, then run all checks
	$(MAKE) fmt
	$(MAKE) check

# Optional, local-only hook. Respect custom hook paths and existing hooks.
precommit-hook: ## Install an optional local pre-commit hook
	@common_dir="$$(git rev-parse --git-common-dir)" || exit; \
	hooks_path="$$(git config --get core.hooksPath || true)"; \
	if [ -n "$$hooks_path" ]; then \
		echo 'core.hooksPath is set; install the hook manually' >&2; exit 1; \
	fi; \
	hook="$$common_dir/hooks/pre-commit"; \
	if [ -e "$$hook" ] || [ -L "$$hook" ]; then \
		echo "$$hook already exists; leaving it unchanged"; \
	else \
		mkdir -p "$$common_dir/hooks" && \
		printf '#!/bin/sh\nexec make check\n' > "$$hook" && \
		chmod +x "$$hook" && echo "installed $$hook"; \
	fi
