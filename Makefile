REQUIRED_TOOLS := aws curl jq docker
BREW_TOOLS := aws jq

.PHONY: check-requirements install-tools new-drill list-drills list-incomplete build-site quiz quiz-aws quiz-k8s quiz-gitlab

check-requirements:
	@echo "Checking for required tools..."
	@for tool in $(REQUIRED_TOOLS) ; do \
		if ! command -v $$tool >/dev/null 2>&1; then \
			echo "Missing required tool: $$tool"; \
			exit 1; \
		fi; \
		echo "✓ $$tool: $$(which $$tool)"; \
	done

install-tools:
	@echo "Installing required tools..."
	@if ! command -v brew >/dev/null 2>&1; then \
		echo "Installing Homebrew..."; \
		/bin/bash -c "$$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; \
	fi
	brew install $(BREW_TOOLS)

new-drill:
	@bash scripts/new-drill.sh

list-drills:
	@printf "%-35s %-12s %-14s %s\n" "NAME" "SECTION" "DIFFICULTY" "STATUS"
	@printf "%-35s %-12s %-14s %s\n" "---" "---" "---" "---"
	@awk '/^  - name:/{name=$$3} /section:/{sec=$$2} /difficulty:/{diff=$$2} /status:/{st=$$2; printf "%-35s %-12s %-14s %s\n", name, sec, diff, st}' drill-index.yaml

list-incomplete:
	@echo "Drills needing work (incomplete or stub):"
	@echo ""
	@awk '/^  - name:/{name=$$3} /section:/{sec=$$2} /status:/{st=$$2; if(st!="complete") printf "  [%s] %-35s (%s)\n", st, name, sec}' drill-index.yaml

build-site:
	@python3 scripts/build-site.py

quiz:
	@bash quizzes/quiz.sh

quiz-aws:
	@bash quizzes/quiz.sh --section aws

quiz-k8s:
	@bash quizzes/quiz.sh --section kubernetes

quiz-gitlab:
	@bash quizzes/quiz.sh --section gitlab
