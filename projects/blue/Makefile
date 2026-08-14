# version     ?=  $(shell git name-rev --tags --name-only $(shell git rev-parse HEAD))# 0.0.1
version     ?=  $(shell jq -r '."projects/blue"' ../../.release-please-manifest.json)
target      ?=  blue
PKG_LDFLAGS := github.com/davidaparicio/microsvcs/projects/blue/internal/version

include ../Makefile.common
