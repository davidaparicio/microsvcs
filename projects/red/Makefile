# version     ?=  $(shell git name-rev --tags --name-only $(shell git rev-parse HEAD))# 0.0.1
version     ?=  $(shell jq -r '."projects/red"' ../../.release-please-manifest.json)
target      ?=  red
PKG_LDFLAGS := github.com/davidaparicio/microsvcs/projects/red/internal/version

include ../Makefile.common
