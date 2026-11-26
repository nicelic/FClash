SHELL := /bin/bash

.PHONY: help update-core

help:
	@echo 'make update-core  # update official mihomo Go core dependency'
	@echo ''
	@echo 'The Go core and Rust helper build automatically through the setup build'
	@echo 'hook during flutter build; see .agents/commands.md.'

update-core:
	cd core && go get github.com/metacubex/mihomo@latest && go mod tidy
