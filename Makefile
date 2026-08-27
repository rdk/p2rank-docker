IMAGE   ?= p2rank:local
VERSION ?= 2.5.1

.PHONY: build test run shell lint clean

build: ## Build the image
	docker build --build-arg P2RANK_VERSION=$(VERSION) -t $(IMAGE) .

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
