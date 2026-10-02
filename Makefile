.PHONY: help
help: ## show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

# Bats files use a test DSL, so syntax-check ordinary Bash files separately.
BASH_FILES := tmux-tabs.sh install.sh update.sh $(wildcard tests/*.sh tests/*.bash)
SHELL_FILES := $(BASH_FILES) $(wildcard tests/*.bats)
BATS := .tools/bats-core/bin/bats

.PHONY: deps
deps: ## install pinned Bats and assertion libraries locally
	bash tests/bootstrap.sh

.PHONY: test
test: ## run isolated Bash tests (run make deps first)
	@test -x "$(BATS)" || { echo 'Run make deps first' >&2; exit 1; }
	@command -v jq >/dev/null || { echo 'jq required' >&2; exit 1; }
	$(BATS) tests

.PHONY: check
check: lint test ## run all checks without modifying files

.PHONY: fmt
fmt: ## format bash files in place
	@command -v shfmt >/dev/null || { echo 'shfmt required' >&2; exit 1; }
	shfmt -ln bash -i 4 -ci -w $(BASH_FILES)
	shfmt -ln bats -i 4 -ci -w $(wildcard tests/*.bats)

.PHONY: lint
lint: ## run shellcheck, syntax and formatting checks
	@command -v shellcheck >/dev/null || { echo 'ShellCheck required' >&2; exit 1; }
	@command -v shfmt >/dev/null || { echo 'shfmt required' >&2; exit 1; }
	@for file in $(BASH_FILES); do bash -n "$$file" || exit; done
	shellcheck -x $(SHELL_FILES)
	shfmt -ln bash -i 4 -ci -d $(BASH_FILES)
	shfmt -ln bats -i 4 -ci -d $(wildcard tests/*.bats)

.PHONY: precommit
precommit: ## format files, then run lint and tests
	$(MAKE) fmt
	$(MAKE) check

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
