# Changelog

## [0.2.3](https://github.com/davidaparicio/microsvcs/compare/git-sync/0.2.2...git-sync/0.2.3) (2026-01-29)


### Bug Fixes

* **git-sync:** make quay.io image ([#97](https://github.com/davidaparicio/microsvcs/issues/97)) ([1b20cfe](https://github.com/davidaparicio/microsvcs/commit/1b20cfed3608b48186ffb15b42778025e8bc0d78))

## [0.2.2](https://github.com/davidaparicio/microsvcs/compare/git-sync/0.2.1...git-sync/0.2.2) (2026-01-29)


### Bug Fixes

* **git-sync:** where /tmp doesn't exist (like minimal containers) ([#94](https://github.com/davidaparicio/microsvcs/issues/94)) ([905d370](https://github.com/davidaparicio/microsvcs/commit/905d3700377a2d45bf5104888dfb601739024dfb))

## [0.2.1](https://github.com/davidaparicio/microsvcs/compare/git-sync/0.2.0...git-sync/0.2.1) (2026-01-29)


### Bug Fixes

* **git-sync:** linter fixes, Error return value of  is not checked (errcheck) ([#92](https://github.com/davidaparicio/microsvcs/issues/92)) ([f28f48f](https://github.com/davidaparicio/microsvcs/commit/f28f48f3c62a7c46df056ba0a37187c540d419a6))

## [0.2.0](https://github.com/davidaparicio/microsvcs/compare/git-sync/0.1.0...git-sync/0.2.0) (2026-01-29)


### Features

* add test coverage reporting to CI and Makefiles ([#68](https://github.com/davidaparicio/microsvcs/issues/68)) ([cb4c7dd](https://github.com/davidaparicio/microsvcs/commit/cb4c7dd2007a4cc346e88356f44dbb90278cf825))
* **git-sync:** new microservice kick-off ([#61](https://github.com/davidaparicio/microsvcs/issues/61)) ([ab53bf8](https://github.com/davidaparicio/microsvcs/commit/ab53bf828287c5cedd297747dbcac4ab7bb9d71e))


### Bug Fixes

* **git-sync:** go fmt ([#69](https://github.com/davidaparicio/microsvcs/issues/69)) ([db6471c](https://github.com/davidaparicio/microsvcs/commit/db6471cb2255a3bf6012b82c461d2e61210f8527))

## 0.1.0 (Unreleased)

### Features

* Initial implementation of git-sync microservice
* Periodic git synchronization with cron scheduling
* Health check endpoints (/healthz, /readyz, /metrics, /version)
* Support for standalone and sidecar deployment modes
* Pure Go implementation using go-git library
* Configuration via environment variables
