# striptracks-standalone

Strips unwanted audio and subtitle tracks from video files using mkvmerge. Point it at a directory, tell it which languages to keep, done. No re-encoding -- streams pass through untouched, just repackaged into MKV.

If you have Radarr/Sonarr, it can pull language preferences from your quality profiles and rescan your library after processing. Or just hardcode `:eng:und` and forget about it.

Forked from [TheCaptain989/radarr-striptracks](https://github.com/TheCaptain989/radarr-striptracks).

## Quick start

```yaml
# docker-compose.yml
services:
  striptracks:
    image: thecaptain989/radarr-striptracks:latest
    environment:
      STRIPTRACKS_AUDIO: ":eng:und"
      STRIPTRACKS_DIR: /movies
    volumes:
      - /path/to/movies:/movies
```

```bash
docker compose run --rm striptracks
```

Processes every video file under `/movies`, keeps English and undefined audio, strips all embedded subtitles, outputs MKV. Shows progress like `[47/2000] Processing: ...` as it goes.

## Run modes

Three modes, controlled by `STRIPTRACKS_MODE`:

**`run`** (default) -- process all files, print summary, exit.

**`wait`** -- process all files, then sit there until you press Enter. Useful when you want the container to stay up for `docker exec` or manual re-triggers.

**`watch`** -- process all files, then monitor the directory for new files using `inotifywait`. When a file appears or changes, wait for it to finish writing (configurable delay), then process it. Runs until you stop the container.

```yaml
# Watch mode example
environment:
  STRIPTRACKS_MODE: watch
  STRIPTRACKS_WATCH_DELAY: 60        # seconds to wait after file detected
  STRIPTRACKS_CACHE_REFRESH: 30      # minutes between API cache refreshes
  STRIPTRACKS_DIR: /movies
  STRIPTRACKS_AUDIO: ":eng:und"
```

## Configuration

CLI flags override env vars. A `docker-compose.yml` example with all options is included in the repo.

### Environment variables

| Variable | Description | Default |
|----------|-------------|---------|
| `STRIPTRACKS_DIR` | Directory to process recursively | (required) |
| `STRIPTRACKS_AUDIO` | Audio languages to keep (e.g., `:eng:und`) | auto-detect from API |
| `STRIPTRACKS_SUBS` | Subtitle languages to keep (empty = strip all) | strip all |
| `STRIPTRACKS_MODE` | Run mode: `run`, `wait`, `watch` | `run` |
| `STRIPTRACKS_WATCH_DELAY` | Seconds to wait after detecting a new file | `60` |
| `STRIPTRACKS_CACHE_REFRESH` | Minutes between API cache refreshes (watch mode) | `30` |
| `STRIPTRACKS_DRY_RUN` | Set `true` to preview without changes | `false` |
| `STRIPTRACKS_TEST` | Set `true` to validate config and exit | `false` |
| `STRIPTRACKS_STATE_FILE` | Path to processed-files state file | `/config/striptracks.state` |
| `STRIPTRACKS_EXCLUDE` | Comma-separated glob patterns to exclude | |
| `STRIPTRACKS_EXTENSIONS` | File extensions to process | `mkv,mp4,avi,wmv,flv,mov,webm` |
| `STRIPTRACKS_REORDER` | Reorder tracks to match language priority | `false` |
| `STRIPTRACKS_DEBUG` | Debug level (0-3) | `0` |
| `STRIPTRACKS_LOG` | Log file path | `/config/logs/striptracks.log` |
| `STRIPTRACKS_PRIORITY` | Process priority: idle, low, medium, high | `medium` |
| `RADARR_URL` | Radarr API URL (e.g., `http://radarr:7878`) | |
| `RADARR_API_KEY` | Radarr API key | |
| `SONARR_URL` | Sonarr API URL (e.g., `http://sonarr:8989`) | |
| `SONARR_API_KEY` | Sonarr API key | |

### Skipping files

The tool tracks which files it has already processed in a state file (default: `/config/striptracks.state`). On re-runs, files with the same path and modification time are skipped. This makes re-runs fast -- only new or changed files get processed.

Disable with `--no-state` if you want to reprocess everything.

### Excluding files

Skip certain paths with glob patterns:

```yaml
STRIPTRACKS_EXCLUDE: "*/extras/*,*/featurettes/*,*/behind the scenes/*"
```

Or on the command line (repeatable):
```bash
--exclude "*/extras/*" --exclude "*/samples/*"
```

### Test mode

Validate your config without processing anything:

```bash
docker compose run --rm striptracks --test
```

Reports binary versions, API connections, library counts, and current settings.

### Language codes

ISO 639-2 codes, prefixed with colons. Concatenate them:

```
:eng          # English only
:eng:und      # English and undefined
:eng:jpn:und  # English, Japanese, and undefined
:any          # keep everything
```

Modifiers go after the code:

| Modifier | Meaning |
|----------|---------|
| `+f` | Only forced tracks |
| `-f` | Exclude forced tracks |
| `+d` | Only default tracks |
| `-d` | Exclude default tracks |
| `+N` | Keep at most N tracks |
| `=name` | Match track name (case-insensitive substring) |

So `:eng+f` is forced English only, `:any+d1` is one default track in any language, `:eng=Commentary` matches English tracks with "Commentary" in the name.

### The `:org` code

`:org` means "whatever the original language of the movie/series is."

With Radarr/Sonarr configured, it looks this up automatically per file. Without the API, pass it manually: `--original-language Japanese`.

## Radarr/Sonarr API

Set `RADARR_URL` + `RADARR_API_KEY` (and/or the Sonarr equivalents) and the tool will cache your library on startup, match each file to a movie or series by path, pull language preferences from the quality profile, resolve `:org`, and trigger a rescan after processing.

Both Radarr and Sonarr can run at the same time. Radarr is checked first. If a file doesn't match anything, it falls back to `STRIPTRACKS_AUDIO`.

In watch mode, the cache refreshes periodically (default every 30 minutes) so newly added movies/series get picked up.

## Dry run

See what would happen without touching anything:

```bash
docker compose run --rm striptracks --dry-run
```

```
[DRY RUN] --- /movies/Movie (2024)/Movie.2024.mkv ---
[DRY RUN]   AUDIO tracks:
[DRY RUN]     [KEEP] Track 1: eng [default]
[DRY RUN]     [STRIP] Track 2: fre
[DRY RUN]   SUBTITLES tracks:
[DRY RUN]     [STRIP] Track 3: eng
[DRY RUN]     [STRIP] Track 4: fre
[DRY RUN] Would keep 1 tracks, remove 3 tracks
```

## Examples

English audio only, nuke all embedded subs:
```yaml
STRIPTRACKS_AUDIO: ":eng:und"
STRIPTRACKS_DIR: /movies
```

Anime -- keep English and Japanese audio, keep English subs (PGS/ASS from Blu-ray):
```yaml
STRIPTRACKS_AUDIO: ":eng:jpn"
STRIPTRACKS_SUBS: ":eng"
STRIPTRACKS_DIR: /anime
```

Let Radarr decide languages, reorder tracks, watch for new files:
```yaml
RADARR_URL: http://radarr:7878
RADARR_API_KEY: abc123
STRIPTRACKS_DIR: /movies
STRIPTRACKS_REORDER: "true"
STRIPTRACKS_MODE: watch
```

Skip extras and featurettes:
```yaml
STRIPTRACKS_AUDIO: ":eng:und"
STRIPTRACKS_DIR: /movies
STRIPTRACKS_EXCLUDE: "*/extras/*,*/featurettes/*"
```

One file:
```bash
docker compose run --rm striptracks -f /movies/movie.mkv -a :eng:und -s :eng
```

## Project structure

```
striptracks-standalone.sh   # Entry point (~80 lines)
lib/
  logging.sh                # Log output, ANSI colors
  cli.sh                    # Argument parsing, help text, exit handling
  language.sh               # Language code parsing and :org resolution
  api.sh                    # Radarr/Sonarr API calls and library caching
  environment.sh            # Binary checks, API setup, test mode
  media.sh                  # Video inspection, language detection
  tracks.sh                 # Track selection (the big jq logic)
  remux.sh                  # mkvmerge execution, file replacement
  directory.sh              # Directory traversal, watch mode, state tracking
Dockerfile
docker-compose.yml          # Example with all options
```

## Dependencies

The container has everything. Outside Docker you need:

- `mkvmerge` and `mkvpropedit` ([mkvtoolnix](https://mkvtoolnix.download/))
- `jq`
- `curl` (only for API features)
- `inotify-tools` (only for watch mode, Linux only)
- `bash` 4+

## How it works

mkvmerge remuxes the file -- copies streams into a new MKV container without the unwanted tracks. No re-encoding, so it runs at disk speed and is lossless. Non-MKV inputs (MP4, AVI, etc.) come out as MKV. The original is deleted after a successful remux.

Files that already have the right tracks and are already MKV get skipped (just a title metadata update).

## License

GPL-3.0-only
