# Changelog

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
