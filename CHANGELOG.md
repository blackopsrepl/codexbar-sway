# Changelog

All notable changes to this project will be documented in this file. See [commit-and-tag-version](https://github.com/absolute-version/commit-and-tag-version) for commit guidelines.

## [1.4.3](https://github.com/blackopsrepl/codexbar-sway/compare/v1.4.2...v1.4.3) (2026-09-17)


### Bug Fixes

* **ui:** keep heatmap peak label inside the stats line 809b8ea

## [1.4.2](https://github.com/blackopsrepl/codexbar-sway/compare/v1.4.1...v1.4.2) (2026-09-17)


### Bug Fixes

* **ui:** stop heatmap stats truncating at panel width b38e70b

## [1.4.1](https://github.com/blackopsrepl/codexbar-sway/compare/v1.4.0...v1.4.1) (2026-09-17)


### Features

* **ui:** add cumulative token heatmap to Overview 47a6c8c

## [1.4.0](https://github.com/blackopsrepl/codexbar-sway/compare/v1.3.0...v1.4.0) (2026-09-17)


### Features

* **ui:** make heatmap dual-metric and polish panel motion 55cedb7


### Bug Fixes

* **ui:** reduce heatmap to one fill ramp and a compact band 2e9b7a2

## [1.3.0](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.5...v1.3.0) (2026-09-17)


### Features

* **ui:** square the panel and add a token usage heatmap c95aa71

## [1.2.5](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.4...v1.2.5) (2026-09-16)


### Bug Fixes

* **history:** re-merge local usage for every scanned day 41a0a12

## [1.2.4](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.3...v1.2.4) (2026-09-16)


### Bug Fixes

* **local-usage:** attribute Codex and Claude local usage to models 2fbfdae

## [1.2.3](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.2...v1.2.3) (2026-09-16)


### Bug Fixes

* **local-usage:** scope OpenCode Go totals to the opencode-go provider 37b6816

## [1.2.2](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.1...v1.2.2) (2026-09-14)


### Features

* **zai:** read zai-routed local usage from the opencode database 2b50fc0


### Bug Fixes

* **opencode:** label the provider OpenCode Go edcb0fa

## [1.2.1](https://github.com/blackopsrepl/codexbar-sway/compare/v1.2.0...v1.2.1) (2026-09-14)


### Bug Fixes

* **presenter:** give every provider an equivalent overview summary 7d3ce02

## [1.2.0](https://github.com/blackopsrepl/codexbar-sway/compare/v1.1.1...v1.2.0) (2026-09-14)


### Features

* **zai:** add Z.ai GLM Coding Plan provider 64b13ab


### Bug Fixes

* **history:** retain consistent history across window and model providers 2619786
* **quickshell:** compact the overview display indicator 80f1d42
* **quickshell:** size history tiles from the layout, not their own grid 6b1bce7

## [1.1.1](https://github.com/blackopsrepl/codexbar-sway/compare/v1.1.0...v1.1.1) (2026-09-14)


### Bug Fixes

* **quickshell:** keep history tiles in fixed columns 7bc30fb
* **quickshell:** stop rewriting ui state on adapter updates 4dc4d3c

## [1.1.0](https://github.com/blackopsrepl/codexbar-sway/compare/v1.0.2...v1.1.0) (2026-09-14)


### Features

* **opencode:** add OpenCode Go quota integration 130cb5e


### Bug Fixes

* **gemini:** surface quota API error details e90d23c

## [1.0.2](https://github.com/blackopsrepl/codexbar-sway/compare/v1.0.1...v1.0.2) (2026-08-25)


### Bug Fixes

* **check:** isolate smoke runtime state 6cf9ce7
* **codex:** adapt quota collection to current app server 34a1600
* **codex:** expose unavailable five-hour quota b4c3b01
* **codex:** remove fabricated quota placeholders c291339
* **codex:** restore truthful missing-window state e1ec596
* **quickshell:** verify the supervised process ea1798e

## [1.0.1](https://github.com/blackopsrepl/codexbar-sway/compare/v1.0.0...v1.0.1) (2026-05-16)


### Bug Fixes

* **cli:** refresh auxiliary snapshots c6e9ddc

## [1.0.0](https://github.com/blackopsrepl/codexbar-sway/compare/v0.1.1...v1.0.0) (2026-05-16)


### Features

* **gemini:** preserve model-level quota and usage 9d3e533
* **ui:** center and harden the QuickShell modal ea28c8e


### Bug Fixes

* **cli:** keep provider activation local 69468d5
* **ui:** keep modal header actions in bounds d858f0d

## 0.1.1 (2026-05-16)


### Features

* establish CodexBar Linux release baseline 201a896
* **runtime:** add auxiliary quota intelligence 94ee4d4
* **ui:** add tabbed QuickShell quota panel c89ca1e


### Bug Fixes

* **providers:** restrict refreshed credential files 9d6a5bd
