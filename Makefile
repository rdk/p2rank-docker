IMAGE ?= p2rank:local

.PHONY: build test run shell lint clean

build: ## Build the image
	docker build -t $(IMAGE) .

test: build ## Build, then run the behavioural test suite
	IMAGE=$(IMAGE) tests/run-tests.sh

run: ## Predict on a structure: make run FILE=1fbl.pdb
	docker run --rm -u $$(id -u):$$(id -g) -v "$$PWD:/data" $(IMAGE) \
		prank predict -f /data/$(FILE) -o /data/p2rank_output

shell: ## Interactive shell in the image
	docker run --rm -it -v "$$PWD:/data" $(IMAGE) bash

# hadolint is pinned to the version hadolint-action uses in ci.yml. An older
# hadolint rejects `ADD --checksum`, so an unpinned local run can disagree with
# CI. Keep the two in step.
lint: ## Lint the Dockerfile and the test script
	docker run --rm -i hadolint/hadolint:v2.15.1 < Dockerfile
	docker run --rm -v "$$PWD:/mnt" koalaman/shellcheck:stable /mnt/tests/run-tests.sh

clean: ## Remove the local image
	-docker rmi $(IMAGE)
