# CodexBar Makefile
# Ruby-only task runner with colorized output

# ============== Colors & Symbols ==============
GREEN := \033[92m
EMERALD := \033[38;2;16;185;129m
CYAN := \033[96m
YELLOW := \033[93m
MAGENTA := \033[95m
RED := \033[91m
GRAY := \033[90m
BOLD := \033[1m
RESET := \033[0m

CHECK := ✓
CROSS := ✗
ARROW := ▸
PROGRESS := →

# ============== Project Metadata ==============
VERSION := $(shell sed -n 's/^MARKETING_VERSION=//p' version.env)
BUILD_NUMBER := $(shell sed -n 's/^BUILD_NUMBER=//p' version.env)

PREFIX ?= $(HOME)/.local
APP_NAME := codexbar
APP_DIR := $(PREFIX)/share/$(APP_NAME)
BIN_DIR := $(PREFIX)/bin
CONFIG ?= $(HOME)/.codexbar/config.json
SOLVERFORGE_PATH ?= $(HOME)/.local/share/solverforge

RUBY_SOURCES := bin/codexbar $(shell rg --files lib test)

INSTALL_FILES := \
	AGENTS.md \
	CHANGELOG.md \
	LICENSE \
	README.md \
	WIREFRAME.md \
	bin/codexbar \
	codexbar-mascot.png \
	codexbar.png \
	version.env \
	docs/DEVELOPMENT.md \
	docs/RELEASING.md \
	docs/architecture.md \
	docs/cli.md \
	docs/configuration.md \
	docs/codexbar.png \
	docs/icon.png \
	docs/index.html \
	docs/installation.md \
	docs/providers.md \
	docs/runtime-contracts.md \
	docs/site.css \
	docs/status.md \
	docs/ui.md \
	frontend/quickshell/shell.qml \
	lib/codexbar.rb \
	lib/codexbar/cli.rb \
	lib/codexbar/core/config.rb \
	lib/codexbar/core/format.rb \
	lib/codexbar/core/http.rb \
	lib/codexbar/core/metric.rb \
	lib/codexbar/core/process.rb \
	lib/codexbar/core/types.rb \
	lib/codexbar/providers/claude.rb \
	lib/codexbar/providers/codex.rb \
	lib/codexbar/providers/gemini.rb \
	lib/codexbar/providers/index.rb \
	lib/codexbar/providers/opencode.rb \
	lib/codexbar/providers/zai.rb \
	lib/codexbar/runtime/daemon.rb \
	lib/codexbar/runtime/history.rb \
	lib/codexbar/runtime/local_usage.rb \
	lib/codexbar/runtime/notifications.rb \
	lib/codexbar/runtime/presenter.rb \
	lib/codexbar/runtime/quickshell.rb \
	lib/codexbar/runtime/server.rb \
	lib/codexbar/runtime/state.rb \
	lib/codexbar/runtime/status.rb \
	lib/codexbar/runtime/storage.rb \
	lib/codexbar/runtime/swaybar.rb \
	lib/codexbar/runtime/usage.rb \
	lib/codexbar/runtime/waybar.rb

# ============== Phony Targets ==============
.PHONY: banner help install uninstall configure-user install-solverforge-linux-integration \
        check check-live lint syntax test smoke waybar-render panel daemon quickshell-load \
        version bump-patch bump-minor bump-major bump-dry

# ============== Default Target ==============
.DEFAULT_GOAL := help

# ============== Banner ==============
banner:
	@printf "$(EMERALD)$(BOLD)"
	@printf "   ______          __          ____            \n"
	@printf "  / ____/___  ____/ /__  _  __/ __ )____ ______\n"
	@printf " / /   / __ \\/ __  / _ \\| |/_/ __  / __ \`/ ___/\n"
	@printf "/ /___/ /_/ / /_/ /  __/>  </ /_/ / /_/ / /    \n"
	@printf "\\____/\\____/\\__,_/\\___/_/|_/_____/\\__,_/_/     \n"
	@printf "$(RESET)"
	@printf "  $(GRAY)v$(VERSION)$(RESET) $(EMERALD)CodexBar Build System$(RESET)\n\n"

# ============== Install Targets ==============

install: banner
	@printf "$(CYAN)$(BOLD)╔══════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)$(BOLD)║         Installing CodexBar          ║$(RESET)\n"
	@printf "$(CYAN)$(BOLD)╚══════════════════════════════════════╝$(RESET)\n\n"
	@printf "$(ARROW) $(BOLD)Staging release files...$(RESET)\n"
	@rm -rf "$(APP_DIR).tmp"
	@mkdir -p "$(APP_DIR).tmp" "$(BIN_DIR)"
	@for path in $(INSTALL_FILES); do \
		mkdir -p "$(APP_DIR).tmp/$$(dirname "$$path")"; \
		cp -p "$$path" "$(APP_DIR).tmp/$$path"; \
	done
	@chmod 0755 "$(APP_DIR).tmp/bin/codexbar"
	@printf "$(ARROW) $(BOLD)Activating install...$(RESET)\n"
	@rm -rf "$(APP_DIR).previous"
	@if [[ -e "$(APP_DIR)" || -L "$(APP_DIR)" ]]; then mv "$(APP_DIR)" "$(APP_DIR).previous"; fi
	@mv "$(APP_DIR).tmp" "$(APP_DIR)"
	@ln -sfn "$(APP_DIR)/bin/codexbar" "$(BIN_DIR)/codexbar"
	@rm -rf "$(APP_DIR).previous"
	@printf "$(GREEN)$(CHECK) Installed codexbar v$(VERSION) to $(APP_DIR)$(RESET)\n"
	@printf "$(GREEN)$(CHECK) Linked $(BIN_DIR)/codexbar$(RESET)\n\n"

uninstall:
	@printf "$(ARROW) Removing CodexBar install...\n"
	@if [[ -L "$(BIN_DIR)/codexbar" && "$$(readlink -f "$(BIN_DIR)/codexbar")" == "$(APP_DIR)/bin/codexbar" ]]; then \
		rm -f "$(BIN_DIR)/codexbar"; \
	fi
	@rm -rf "$(APP_DIR)"
	@printf "$(GREEN)$(CHECK) CodexBar uninstalled$(RESET)\n"

configure-user:
	@printf "$(ARROW) Pointing user config at the installed QuickShell shell...\n"
	@if [[ ! -x "$(BIN_DIR)/codexbar" ]]; then \
		printf "$(RED)$(CROSS) Run make install before make configure-user.$(RESET)\n" >&2; \
		exit 1; \
	fi
	@if [[ ! -f "$(CONFIG)" ]]; then "$(BIN_DIR)/codexbar" config init --config "$(CONFIG)" >/dev/null; fi
	@ruby -rjson -rfileutils -e 'path, shell = ARGV; data = JSON.parse(File.read(path)); data["runtime"] ||= {}; data["runtime"]["quickShellShell"] = File.expand_path(shell); FileUtils.mkdir_p(File.dirname(path)); File.write(path, JSON.pretty_generate(data) + "\n"); File.chmod(0o600, path)' "$(CONFIG)" "$(APP_DIR)/frontend/quickshell/shell.qml"
	@printf "$(GREEN)$(CHECK) User config updated: $(CONFIG)$(RESET)\n"

install-solverforge-linux-integration:
	@printf "$(ARROW) Installing SolverForge Waybar wrapper...\n"
	@mkdir -p "$(SOLVERFORGE_PATH)/bin"
	@install -m 0755 packaging/solverforge-linux/solverforge-waybar-codexbar "$(SOLVERFORGE_PATH)/bin/solverforge-waybar-codexbar"
	@if [[ -f "$(SOLVERFORGE_PATH)/default/waybar/config" ]]; then \
		rg -q '"custom/codexbar"' "$(SOLVERFORGE_PATH)/default/waybar/config"; \
	fi
	@printf "$(GREEN)$(CHECK) Wrapper installed to $(SOLVERFORGE_PATH)/bin/solverforge-waybar-codexbar$(RESET)\n"

# ============== Validation Targets ==============

check: banner
	@printf "$(CYAN)$(BOLD)╔══════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)$(BOLD)║            Release Check             ║$(RESET)\n"
	@printf "$(CYAN)$(BOLD)╚══════════════════════════════════════╝$(RESET)\n\n"
	@printf "$(ARROW) $(BOLD)Running bin/release-check...$(RESET)\n"
	@bin/release-check && \
		printf "\n$(GREEN)$(BOLD)$(CHECK) Release check passed$(RESET)\n\n" || \
		(printf "\n$(RED)$(CROSS) Release check failed$(RESET)\n\n" && exit 1)

check-live: banner
	@printf "$(CYAN)$(BOLD)╔══════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)$(BOLD)║         Live Release Check           ║$(RESET)\n"
	@printf "$(CYAN)$(BOLD)╚══════════════════════════════════════╝$(RESET)\n\n"
	@printf "$(ARROW) $(BOLD)Running bin/release-check --with-live...$(RESET)\n"
	@bin/release-check --with-live && \
		printf "\n$(GREEN)$(BOLD)$(CHECK) Live release check passed$(RESET)\n\n" || \
		(printf "\n$(RED)$(CROSS) Live release check failed$(RESET)\n\n" && exit 1)

lint:
	@printf "$(PROGRESS) Running pre-commit hooks...\n"
	@python3 -m pre_commit run --all-files && \
		printf "$(GREEN)$(CHECK) Lint passed$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Lint failed$(RESET)\n" && exit 1)

syntax:
	@printf "$(PROGRESS) Checking Bash syntax...\n"
	@bash -n bin/release-check && \
		printf "$(GREEN)$(CHECK) Bash syntax valid$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Bash syntax errors found$(RESET)\n" && exit 1)
	@printf "$(PROGRESS) Checking Ruby syntax per file...\n"
	@for path in $(RUBY_SOURCES); do ruby -wc "$$path"; done && \
		printf "$(GREEN)$(CHECK) Ruby syntax valid ($(words $(RUBY_SOURCES)) files)$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Ruby syntax errors found$(RESET)\n" && exit 1)

test: banner
	@printf "$(CYAN)$(BOLD)╔══════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)$(BOLD)║          Ruby Test Suite             ║$(RESET)\n"
	@printf "$(CYAN)$(BOLD)╚══════════════════════════════════════╝$(RESET)\n\n"
	@printf "$(ARROW) $(BOLD)Running all tests...$(RESET)\n"
	@ruby -Itest test/run.rb && \
		printf "\n$(GREEN)$(CHECK) All tests passed$(RESET)\n\n" || \
		(printf "\n$(RED)$(CROSS) Tests failed$(RESET)\n\n" && exit 1)

smoke: banner
	@printf "$(CYAN)$(BOLD)╔══════════════════════════════════════╗$(RESET)\n"
	@printf "$(CYAN)$(BOLD)║           CLI Smoke Checks           ║$(RESET)\n"
	@printf "$(CYAN)$(BOLD)╚══════════════════════════════════════╝$(RESET)\n\n"
	@printf "$(ARROW) $(BOLD)Exercising CLI commands in a sandboxed HOME...$(RESET)\n"
	@tmp_root="$$(mktemp -d -t codexbar-smoke-XXXXXX)"; \
	trap 'rm -rf "$$tmp_root"' EXIT; \
	tmp_config="$$tmp_root/config.json"; \
	HOME="$$tmp_root" bin/codexbar config init --config "$$tmp_config" >/dev/null; \
	HOME="$$tmp_root" bin/codexbar config validate --config "$$tmp_config"; \
	HOME="$$tmp_root" bin/codexbar config dump --config "$$tmp_config" --format json >/dev/null; \
	HOME="$$tmp_root" bin/codexbar waybar render --config "$$tmp_config" >/dev/null; \
	HOME="$$tmp_root" bin/codexbar ui status --config "$$tmp_config" --format json --pretty >/dev/null; \
	HOME="$$tmp_root" bin/codexbar history --config "$$tmp_config" --format json >/dev/null; \
	HOME="$$tmp_root" bin/codexbar cost --cached --config "$$tmp_config" --format json >/dev/null; \
	HOME="$$tmp_root" bin/codexbar status --cached --config "$$tmp_config" --format json >/dev/null; \
	HOME="$$tmp_root" bin/codexbar cache clear all --config "$$tmp_config" --format json >/dev/null; \
	printf "$(GREEN)$(CHECK) CLI smoke passed$(RESET)\n\n"

# ============== Runtime Targets ==============

daemon:
	@printf "$(ARROW) Starting the CodexBar daemon (Ctrl+C to stop)...\n"
	@bin/codexbar daemon

panel:
	@printf "$(ARROW) Opening the QuickShell panel...\n"
	@bin/codexbar panel

waybar-render:
	@printf "$(PROGRESS) Rendering Waybar JSON from cached state...\n"
	@bin/codexbar waybar render

quickshell-load:
	@printf "$(ARROW) Loading the source-tree QuickShell panel...\n"
	@env QT_QPA_PLATFORM=wayland CODEXBAR_BIN="$(PWD)/bin/codexbar" CODEXBAR_CONFIG="$(CONFIG)" CODEXBAR_STATE_DIR="$(HOME)/.local/state/codexbar" quickshell --path "$(PWD)/frontend/quickshell/shell.qml"

# ============== Version Management ==============

version:
	@printf "$(CYAN)Current version:$(RESET) $(YELLOW)$(BOLD)v$(VERSION)$(RESET) $(GRAY)(build $(BUILD_NUMBER))$(RESET)\n"

bump-patch: banner
	@printf "$(ARROW) Bumping patch version...\n"
	@npx commit-and-tag-version --release-as patch && \
		printf "$(GREEN)$(CHECK) Version bumped$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Version bump failed$(RESET)\n" && exit 1)

bump-minor: banner
	@printf "$(ARROW) Bumping minor version...\n"
	@npx commit-and-tag-version --release-as minor && \
		printf "$(GREEN)$(CHECK) Version bumped$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Version bump failed$(RESET)\n" && exit 1)

bump-major: banner
	@printf "$(ARROW) Bumping major version...\n"
	@npx commit-and-tag-version --release-as major && \
		printf "$(GREEN)$(CHECK) Version bumped$(RESET)\n" || \
		(printf "$(RED)$(CROSS) Version bump failed$(RESET)\n" && exit 1)

bump-dry:
	@npx commit-and-tag-version --dry-run

# ============== Help ==============

help: banner
	@/bin/echo -e "$(CYAN)$(BOLD)Install & Setup:$(RESET)"
	@/bin/echo -e "  $(GREEN)make install$(RESET)                               - Install CodexBar into ~/.local"
	@/bin/echo -e "  $(GREEN)make configure-user$(RESET)                        - Point user config at the installed shell"
	@/bin/echo -e "  $(GREEN)make install-solverforge-linux-integration$(RESET) - Install the SolverForge Waybar wrapper"
	@/bin/echo -e "  $(GREEN)make uninstall$(RESET)                             - Remove the installed app and link"
	@/bin/echo -e ""
	@/bin/echo -e "$(CYAN)$(BOLD)Validation & Tests:$(RESET)"
	@/bin/echo -e "  $(GREEN)make syntax$(RESET)      - Bash plus per-file Ruby syntax checks"
	@/bin/echo -e "  $(GREEN)make test$(RESET)        - Run the Ruby test suite"
	@/bin/echo -e "  $(GREEN)make smoke$(RESET)       - CLI smoke checks in a sandboxed HOME"
	@/bin/echo -e "  $(GREEN)make lint$(RESET)        - Run pre-commit hooks"
	@/bin/echo -e "  $(GREEN)make check$(RESET)       - $(YELLOW)$(BOLD)Full release gate via bin/release-check$(RESET)"
	@/bin/echo -e "  $(GREEN)make check-live$(RESET)  - $(RED)$(BOLD)Release gate plus live provider checks$(RESET)"
	@/bin/echo -e ""
	@/bin/echo -e "$(CYAN)$(BOLD)Runtime & UI:$(RESET)"
	@/bin/echo -e "  $(GREEN)make daemon$(RESET)          - Run the fetch daemon"
	@/bin/echo -e "  $(GREEN)make panel$(RESET)           - Open the QuickShell panel"
	@/bin/echo -e "  $(GREEN)make waybar-render$(RESET)   - Render Waybar JSON from cached state"
	@/bin/echo -e "  $(GREEN)make quickshell-load$(RESET) - Load the source-tree panel"
	@/bin/echo -e ""
	@/bin/echo -e "$(CYAN)$(BOLD)Version Management:$(RESET)"
	@/bin/echo -e "  $(GREEN)make version$(RESET)      - Show the current version"
	@/bin/echo -e "  $(GREEN)make bump-patch$(RESET)   - Bump patch version (1.2.$(YELLOW)x$(RESET))"
	@/bin/echo -e "  $(GREEN)make bump-minor$(RESET)   - Bump minor version (1.$(YELLOW)x$(RESET).0)"
	@/bin/echo -e "  $(GREEN)make bump-major$(RESET)   - Bump major version ($(YELLOW)x$(RESET).0.0)"
	@/bin/echo -e "  $(GREEN)make bump-dry$(RESET)     - Preview the next release"
	@/bin/echo -e ""
	@/bin/echo -e "$(GRAY)Runtime stack: Ruby + QuickShell + Waybar$(RESET)"
	@/bin/echo -e "$(GRAY)Current version: v$(VERSION) (build $(BUILD_NUMBER))$(RESET)"
	@/bin/echo -e ""
