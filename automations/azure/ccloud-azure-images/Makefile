.PHONY: all
all: lint format

.PHONY: format
format:
	find . -type f -name "*.sh" -exec shfmt --diff --case-indent --indent 2 -w {} \;

.PHONY: lint
lint:
	find . -type f -name "*.sh" -exec shellcheck {} \;
