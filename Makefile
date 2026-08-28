IMAGE   ?= p2rank:local
# The Dockerfile pins the packaged release; derive from it rather than repeating it.
VERSION := $(shell sed -n 's/^ARG P2RANK_VERSION=//p' Dockerfile)

.PHONY: build test run shell lint clean

build: ## Build the image
	docker build -t $(IMAGE) .

test: build ## Build, then run the behavioural test suite
	IMAGE=$(IMAGE) EXPECTED_VERSION=$(VERSION) tests/run-tests.sh

run: ## Predict on a structure: make run FILE=1fbl.pdb
	docker run --rm -u $$(id -u):$$(id -g) -v "$$PWD:/data" $(IMAGE) \
		prank predict -f /data/$(FILE) -o /data/p2rank_output

shell: ## Interactive shell in the image
	docker run --rm -it -v "$$PWD:/data" $(IMAGE) bash

lint: ## Lint the Dockerfile and the test script
	docker run --rm -i -v "$$PWD/.hadolint.yaml:/.hadolint.yaml" hadolint/hadolint < Dockerfile
	docker run --rm -v "$$PWD:/mnt" koalaman/shellcheck:stable /mnt/tests/run-tests.sh

clean: ## Remove the local image
	-docker rmi $(IMAGE)
