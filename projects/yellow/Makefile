# version     ?=  $(shell git name-rev --tags --name-only $(shell git rev-parse HEAD))# 0.0.1
version     ?=  $(shell jq -r '."projects/yellow"' ../../.release-please-manifest.json)
target      ?=  yellow
PKG_LDFLAGS := github.com/davidaparicio/microsvcs/projects/yellow/internal/version

include ../Makefile.common
