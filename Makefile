default := all

.PHONY: all
all: lint format

.PHONY: format
format:
	find automations -type f -name "*.sh" -exec shfmt --diff --case-indent --indent 2 -w {} \;
	find automations -type f -name "*.bicep" -exec az bicep format --file {} \;

.PHONY: lint
lint:
	find automations -type f -name "*.sh" -exec shellcheck {} \;
