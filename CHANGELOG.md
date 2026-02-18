# Changelog

All notable changes to the hecate CLI will be documented in this file.

## [0.1.0] - 2026-02-18

### Added

- Initial release of the standalone hecate CLI
- Node commands: `status`, `health`, `identity`, `version`
- Service commands: `start`, `stop`, `restart`, `logs`, `update`
- Plugin commands: `plugins`, `install`, `remove`
- Plugin subcommand delegation: `hecate <plugin> <subcommand>`
- System commands: `reconcile`, `help`
- Plugin registry with trader and martha plugins
- GitHub Actions release workflow
- Colored terminal output with graceful fallback
- Smart service name resolution (short names to systemd units)
- Plugin install flow: fetch from hecate-gitops, seed directories, reconcile
- Plugin removal with data directory preservation
