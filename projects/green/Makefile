# version     ?=  $(shell git name-rev --tags --name-only $(shell git rev-parse HEAD))# 0.0.1
version     ?=  $(shell jq -r '."projects/green"' ../../.release-please-manifest.json)
target      ?=  green
PKG_LDFLAGS := github.com/davidaparicio/microsvcs/projects/green/internal/version

include ../Makefile.common
