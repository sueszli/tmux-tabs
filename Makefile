SHELL := /bin/bash
.DEFAULT_GOAL := help

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
SH_FILES := tmux-tabs.sh install.sh update.sh $(wildcard tests/*.sh)
SHFMT_FLAGS := -i 4 -ci

.PHONY: help
help: ## show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

.PHONY: fmt
fmt: ## format bash files in place
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	$(SHFMT) $(SHFMT_FLAGS) -w $(SH_FILES)

.PHONY: lint
lint: ## run shellcheck, syntax and formatting checks
	@command -v $(SHELLCHECK) >/dev/null || { echo 'ShellCheck required (see README)' >&2; exit 1; }
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	@for file in $(SH_FILES); do bash -n "$$file" || exit; done
	$(SHELLCHECK) $(SH_FILES)
	$(SHFMT) $(SHFMT_FLAGS) -d $(SH_FILES)

.PHONY: precommit
precommit: ## format files, then run lint checks
	$(MAKE) fmt
	$(MAKE) lint

.PHONY: precommit-hook
precommit-hook: ## install an optional local pre-commit hook
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
		printf '#!/bin/sh\nexec make lint\n' > "$$hook" && \
		chmod +x "$$hook" && echo "installed $$hook"; \
	fi
