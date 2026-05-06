SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

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
	lib/codexbar/runtime/daemon.rb \
	lib/codexbar/runtime/presenter.rb \
	lib/codexbar/runtime/quickshell.rb \
	lib/codexbar/runtime/state.rb \
	lib/codexbar/runtime/swaybar.rb \
	lib/codexbar/runtime/usage.rb \
	lib/codexbar/runtime/waybar.rb

.PHONY: install uninstall configure-user install-solverforge-linux-integration check check-live lint syntax test smoke waybar-render panel daemon quickshell-load

install:
	rm -rf "$(APP_DIR).tmp"
	mkdir -p "$(APP_DIR).tmp" "$(BIN_DIR)"
	for path in $(INSTALL_FILES); do \
		mkdir -p "$(APP_DIR).tmp/$$(dirname "$$path")"; \
		cp -p "$$path" "$(APP_DIR).tmp/$$path"; \
	done
	chmod 0755 "$(APP_DIR).tmp/bin/codexbar"
	rm -rf "$(APP_DIR).previous"
	if [[ -e "$(APP_DIR)" || -L "$(APP_DIR)" ]]; then mv "$(APP_DIR)" "$(APP_DIR).previous"; fi
	mv "$(APP_DIR).tmp" "$(APP_DIR)"
	ln -sfn "$(APP_DIR)/bin/codexbar" "$(BIN_DIR)/codexbar"
	rm -rf "$(APP_DIR).previous"

uninstall:
	if [[ -L "$(BIN_DIR)/codexbar" && "$$(readlink -f "$(BIN_DIR)/codexbar")" == "$(APP_DIR)/bin/codexbar" ]]; then \
		rm -f "$(BIN_DIR)/codexbar"; \
	fi
	rm -rf "$(APP_DIR)"

configure-user:
	[[ -x "$(BIN_DIR)/codexbar" ]] || { echo "Run make install before make configure-user." >&2; exit 1; }
	if [[ ! -f "$(CONFIG)" ]]; then "$(BIN_DIR)/codexbar" config init --config "$(CONFIG)" >/dev/null; fi
	ruby -rjson -rfileutils -e 'path, shell = ARGV; data = JSON.parse(File.read(path)); data["runtime"] ||= {}; data["runtime"]["quickShellShell"] = File.expand_path(shell); FileUtils.mkdir_p(File.dirname(path)); File.write(path, JSON.pretty_generate(data) + "\n"); File.chmod(0o600, path)' "$(CONFIG)" "$(APP_DIR)/frontend/quickshell/shell.qml"

install-solverforge-linux-integration:
	mkdir -p "$(SOLVERFORGE_PATH)/bin"
	install -m 0755 packaging/solverforge-linux/solverforge-waybar-codexbar "$(SOLVERFORGE_PATH)/bin/solverforge-waybar-codexbar"
	if [[ -f "$(SOLVERFORGE_PATH)/default/waybar/config" ]]; then \
		rg -q '"custom/codexbar"' "$(SOLVERFORGE_PATH)/default/waybar/config"; \
	fi

check:
	bin/release-check

check-live:
	bin/release-check --with-live

lint:
	python3 -m pre_commit run --all-files

syntax:
	bash -n bin/release-check
	for path in $(RUBY_SOURCES); do ruby -wc "$$path"; done

test:
	ruby -Itest test/run.rb

smoke:
	tmp_config="$$(mktemp -t codexbar-smoke-XXXXXX.json)"; \
	trap 'rm -f "$$tmp_config"' EXIT; \
	bin/codexbar config init --config "$$tmp_config" >/dev/null; \
	bin/codexbar config validate --config "$$tmp_config"; \
	bin/codexbar waybar render --config "$$tmp_config" >/dev/null; \
	bin/codexbar ui status --config "$$tmp_config" --format json --pretty >/dev/null

waybar-render:
	bin/codexbar waybar render

panel:
	bin/codexbar panel

daemon:
	bin/codexbar daemon

quickshell-load:
	env QT_QPA_PLATFORM=wayland CODEXBAR_BIN="$(PWD)/bin/codexbar" CODEXBAR_CONFIG="$(CONFIG)" CODEXBAR_STATE_DIR="$(HOME)/.local/state/codexbar" quickshell --path "$(PWD)/frontend/quickshell/shell.qml"
