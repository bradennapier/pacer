.PHONY: test install uninstall lint help

PREFIX ?= /usr/local

help:
	@echo "pacer - single-flight debounce/throttle for shell scripts"
	@echo ""
	@echo "Usage:"
	@echo "  make test      Run test suite (requires bats-core)"
	@echo "  make lint      Check bash syntax"
	@echo "  make install   Install to $(PREFIX)/bin"
	@echo "  make uninstall Remove from $(PREFIX)/bin"
	@echo ""
	@echo "Variables:"
	@echo "  PREFIX         Installation prefix (default: /usr/local)"

test:
	@command -v bats >/dev/null 2>&1 || { echo "Install bats-core: brew install bats-core"; exit 1; }
	bats test/pacer.bats

lint:
	@bash -n pacer && echo "pacer: syntax OK"

install: lint
	@mkdir -p $(PREFIX)/bin
	@cp pacer $(PREFIX)/bin/pacer
	@chmod +x $(PREFIX)/bin/pacer
	@echo "Installed to $(PREFIX)/bin/pacer"

uninstall:
	@rm -f $(PREFIX)/bin/pacer
	@echo "Removed $(PREFIX)/bin/pacer"
