.PHONY: help fmt lint precommit precommit-hook
SHELL_FILES := tmux-tabs.sh install.sh update.sh $(wildcard tests/*.sh)

help: ## show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

fmt: ## format bash files in place
	@command -v shfmt >/dev/null || { echo 'shfmt required' >&2; exit 1; }
	shfmt -i 4 -ci -w $(SHELL_FILES)

lint: ## run shellcheck, syntax and formatting checks
	@command -v shellcheck >/dev/null || { echo 'ShellCheck required' >&2; exit 1; }
	@command -v shfmt >/dev/null || { echo 'shfmt required' >&2; exit 1; }
	@for file in $(SHELL_FILES); do bash -n "$$file" || exit; done
	shellcheck $(SHELL_FILES)
	shfmt -i 4 -ci -d $(SHELL_FILES)

precommit: ## format files, then run lint checks
	$(MAKE) fmt
	$(MAKE) lint

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
