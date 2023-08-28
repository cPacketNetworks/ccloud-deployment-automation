.PHONY: all
all: build format

.PHONY: build
build: format
	az bicep build --file main.bicep

.PHONY: format
format:
	az bicep format --file main.bicep

.PHONY: json
json:
	jq -r '.' parameters.json | sponge parameters.json
