.PHONY: help
help: ## show available targets
	@printf 'Usage: make <target>\n\nAvailable targets:\n'
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-20s %s\n", $$1, $$2}'

.PHONY: deps
deps: ## install pinned bats and assertion libraries locally
	bash tests/bootstrap.sh

.PHONY: tests
tests: ## run isolated bash tests (run make deps first)
	@test -x ".tools/bats-core/bin/bats" || { echo 'Run make deps first' >&2; exit 1; }
	@command -v jq >/dev/null || { echo 'jq required' >&2; exit 1; }
	.tools/bats-core/bin/bats tests
	bash tests/shared-rules.sh
	bash tests/install-guardrails.sh

.PHONY: fmt
fmt: ## format bash files in place
	@command -v shfmt >/dev/null || { echo 'shfmt required' >&2; exit 1; }
	shfmt -ln bash -i 4 -ci -w tmux-tabs.sh guardrails.sh install.sh update.sh $(wildcard tests/*.sh)
	shfmt -ln bats -i 4 -ci -w $(wildcard tests/*.bats)

.PHONY: lint
lint: ## run shellcheck and syntax checks
	@command -v shellcheck >/dev/null || { echo 'ShellCheck required' >&2; exit 1; }
	@for file in tmux-tabs.sh guardrails.sh install.sh update.sh $(wildcard tests/*.sh); do bash -n "$$file" || exit; done
	shellcheck -x tmux-tabs.sh guardrails.sh install.sh update.sh $(wildcard tests/*.sh) $(wildcard tests/*.bats)

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
