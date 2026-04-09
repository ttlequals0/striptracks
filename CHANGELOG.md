# Changelog

## 1.0.5 (2026-04-09)

### Fixed

- Log output to Docker now uses stderr (the log function runs in a piped subshell where stdout is consumed by the pipe and never reaches Docker's log driver)

## 1.0.4 (2026-04-09)

### Fixed

- Wait mode (`STRIPTRACKS_MODE=wait`) no longer exits immediately when running detached (`docker compose up -d`). Uses `sleep infinity` with signal trapping instead of `read` when no terminal is attached.

## 1.0.3 (2026-04-09)

### Fixed

- Log output now writes to both file and stdout so Docker log drivers (Loki, etc.) can collect it

## 1.0.2 (2026-04-09)

### Fixed

- Dry-run no longer writes to the state file (was incorrectly recording files as processed during preview)

## 1.0.1 (2026-04-09)

### Fixed

- Log directory auto-created with `mkdir -p` (no more errors when `/config/logs/` doesn't exist)
- Log function handles write failures gracefully instead of spewing errors to stderr
- File extension matching is now case-insensitive (`-iname` instead of `-name`). Files like `.MKV` and `.Mkv` are now found.

## 1.0.0 (2026-04-09)

Initial release of the standalone fork.

### What changed from the original radarr-striptracks

- Forked from [TheCaptain989/radarr-striptracks](https://github.com/TheCaptain989/radarr-striptracks) v3.0
- Removed inline Radarr/Sonarr webhook integration (no more Custom Script / Import mode)
- Rebuilt as a standalone directory-processing tool

### Features

- **Directory processing** -- recursively scan and process all video files in a directory
- **Run modes** -- `run` (process and exit), `wait` (process and pause), `watch` (monitor for new files with inotifywait)
- **Dry-run mode** -- preview track keep/strip decisions without modifying files
- **Test mode** -- validate config, API connections, and binary dependencies
- **Progress counter** -- shows `[47/2000]` per file during batch processing
- **State tracking** -- skip already-processed files on re-runs (path + mtime based)
- **Exclude patterns** -- skip files matching glob patterns (e.g., `*/extras/*`)
- **Radarr/Sonarr API** -- optional auto-detection of languages from quality profiles, `:org` resolution, library rescans
- **Sonarr episodefile caching** -- one API call per series instead of per episode
- **Watch mode cache refresh** -- periodically re-fetches library data from APIs
- **Modular architecture** -- 9 lib/ modules sourced by a slim entry point
- **All config via env vars** -- docker-compose friendly, CLI flags override

### Removed

- Radarr/Sonarr Custom Script mode
- Import Using Script mode
- config.xml parsing
- WSL support
- hotio container support
- Quality profile skip (`--skip-profile`)
- Recycle bin integration (`--disable-recycle`)
