SHELL := /bin/bash
.DEFAULT_GOAL := help

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
SH_FILES := tmux-tabs.sh install.sh update.sh $(wildcard tests/*.sh)
SHFMT_FLAGS := -i 4 -ci

.PHONY: help fmt lint

help: ## show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

fmt: ## format bash files in place
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	$(SHFMT) $(SHFMT_FLAGS) -w $(SH_FILES)

lint: ## run shellcheck, syntax and formatting checks
	@command -v $(SHELLCHECK) >/dev/null || { echo 'ShellCheck required (see README)' >&2; exit 1; }
	@command -v $(SHFMT) >/dev/null || { echo 'shfmt required (see README)' >&2; exit 1; }
	@for file in $(SH_FILES); do bash -n "$$file" || exit; done
	$(SHELLCHECK) $(SH_FILES)
	$(SHFMT) $(SHFMT_FLAGS) -d $(SH_FILES)
