.PHONY: lint

lint:
	shellcheck --check-sourced --enable=all --shell=sh --external-sources bin/pocus
