# ---------------------------------------------------------------------------- #
#                          Git-Sync Microservice Makefile                      #
# ---------------------------------------------------------------------------- #

all: compile check-format lint test

# Variables and Settings
version     ?=  $(shell jq -r '."projects/git-sync"' ../../.release-please-manifest.json)
target      ?=  git-sync
org         ?=  davidaparicio
authorname  ?=  David Aparicio
authoremail ?=  david.aparicio@free.fr
license     ?=  Apache-2.0
year        ?=  2026
copyright   ?=  Copyright (c) $(year)

COMMIT      := $(shell git rev-parse HEAD)
DATE        := $(shell date +%Y-%m-%dT%H:%M:%S%z)
IMAGE_NAME  := $(shell basename $(PWD))
PORTP       := 8080
PORTT       := 8080

PKG_LDFLAGS := github.com/davidaparicio/microsvcs/projects/git-sync/internal/version
CGO_ENABLED := 0
export CGO_ENABLED

compile: mod ## Compile for the local architecture
	@echo "Compiling..."
	go build -ldflags "\
	-s -w \
	-X '${PKG_LDFLAGS}.Version=v$(version)' \
	-X '${PKG_LDFLAGS}.BuildDate=$(DATE)' \
	-X '${PKG_LDFLAGS}.GitCommit=$(COMMIT)'" \
	-o bin/$(target) .

.PHONY: run
run: ## Run the service
	@echo "Running...\n"
	@go run -ldflags "\
	-s -w \
	-X '${PKG_LDFLAGS}.Version=v$(version)' \
	-X '${PKG_LDFLAGS}.BuildDate=$(DATE)' \
	-X '${PKG_LDFLAGS}.GitCommit=$(COMMIT)'" \
	main.go

.PHONY: dockerbuild
dockerbuild: ## Docker build
	docker build -f docker/Dockerfile -t $(IMAGE_NAME) .

.PHONY: docker
docker: ## Docker run
	docker run -it --rm -p $(PORTP):$(PORTT) \
	  -e GIT_REPO_URL=https://github.com/davidaparicio/microsvcs.git \
	  -e TARGET_PATH=/data \
	  $(IMAGE_NAME)

.PHONY: dockerfull
dockerfull: dockerbuild docker ## Docker build and run

.PHONY: mod
mod: ## Go mod things
	go mod tidy
	go get ./...

.PHONY: test
test: compile ## Run go tests
	@echo "Testing..."
	go test -v ./...

.PHONY: clean
clean: ## Clean artifacts
	@echo "Cleaning..."
	rm -rvf dist/*
	rm -rvf bin/*

.PHONY: format
format: ## Format the code using gofmt
	@echo "Formatting..."
	@gofmt -s -w $(shell find . -name '*.go' -not -path "./vendor/*")

.PHONY: check-format
check-format: ## Check if code is formatted
	@gofmt -l $(shell find . -name '*.go' -not -path "./vendor/*") | grep ".*" ; if [ $$? -eq 0 ]; then exit 1; fi

.PHONY: lint
lint: ## Run linter
	golangci-lint run

.PHONY: help
help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(firstword $(MAKEFILE_LIST)) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[32m%-30s\033[0m %s\n", $$1, $$2}'
