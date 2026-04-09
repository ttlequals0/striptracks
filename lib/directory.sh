#!/bin/bash
# striptracks - Directory
# Video file detection, single-file processing pipeline, and recursive directory scanning.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function is_already_processed {
  # Check if file was already processed (same path and mtime in state file)
  local filepath="$1"
  [ -z "$striptracks_state_file" ] && return 1
  [ ! -f "$striptracks_state_file" ] && return 1
  local mtime
  mtime=$(stat -c %Y "$filepath" 2>/dev/null) || return 1
  grep -qF "${mtime}|${filepath}" "$striptracks_state_file"
}
function record_processed {
  # Record a processed file in the state file
  local filepath="$1"
  [ -z "$striptracks_state_file" ] && return
  local mtime
  mtime=$(stat -c %Y "$filepath" 2>/dev/null) || return
  # Ensure state file directory exists
  local state_dir
  state_dir="$(dirname "$striptracks_state_file")"
  [ -n "$state_dir" ] && [ ! -d "$state_dir" ] && mkdir -p "$state_dir" 2>/dev/null
  # Remove old entry for this path, then append new one
  if [ -f "$striptracks_state_file" ]; then
    grep -v "|${filepath}$" "$striptracks_state_file" > "${striptracks_state_file}.tmp" 2>/dev/null || true
    mv -f "${striptracks_state_file}.tmp" "$striptracks_state_file"
  fi
  echo "${mtime}|${filepath}" >> "$striptracks_state_file"
}
function is_video_file {
  local file="$1"
  local ext="${file##*.}"
  ext="${ext,,}" # lowercase
  [[ ",$striptracks_extensions," == *",$ext,"* ]]
}
function process_single_file {
  # Process a single video file through the full pipeline

  local filepath="$1"

  export striptracks_video="$filepath"
  export striptracks_title="$(basename "$filepath" ".${filepath##*.}")"
  export striptracks_newvideo="${filepath%.*}.mkv"
  unset striptracks_tempvideo striptracks_json striptracks_json_processed
  unset striptracks_order striptracks_neworder
  unset striptracks_mkvmerge_default_args striptracks_mkvpropedit_default_args

  # Save original language settings (may be modified per-file by match_file_to_media)
  local orig_audiokeep="$striptracks_audiokeep"
  local orig_subskeep="$striptracks_subskeep"
  local orig_originalLangCode="$striptracks_originalLangCode"
  local orig_profileLangCodes="$striptracks_profileLangCodes"

  _restore_lang_state() {
    export striptracks_audiokeep="$orig_audiokeep"
    export striptracks_subskeep="$orig_subskeep"
    export striptracks_originalLangCode="$orig_originalLangCode"
    export striptracks_profileLangCodes="$orig_profileLangCodes"
  }

  local filesize
  filesize=$(stat -c %s "$filepath" 2>/dev/null | numfmt --to iec --format "%.3f" 2>/dev/null) || filesize="unknown"
  local progress=""
  [ -n "$striptracks_file_total" ] && [ "$striptracks_file_total" -gt 0 ] && progress="[$striptracks_file_count/$striptracks_file_total] "
  echo "Info|${progress}Processing: $filepath ($filesize)" | log

  # Match to Radarr/Sonarr if API available
  if [ -n "$striptracks_radarr_cache" ] || [ -n "$striptracks_sonarr_cache" ]; then
    match_file_to_media "$filepath"
    if [ "$striptracks_matched" = "true" ] && [ -z "$orig_audiokeep" ]; then
      detect_languages
    fi
  fi

  check_video

  process_org_code "audio" "striptracks_audiokeep"
  process_org_code "subtitles" "striptracks_subskeep"
  process_org_code "audio" "striptracks_default_audio"
  process_org_code "subtitles" "striptracks_default_subtitles"

  resolve_code_conflict
  local return=$?
  if [ $return -ne 0 ]; then
    _restore_lang_state
    return $return
  fi

  get_mediainfo "$striptracks_video"
  process_mkvmerge_json

  # Dry-run: report and skip remux
  if [ "$striptracks_dry_run" = "true" ]; then
    echo "Info|[DRY RUN] --- $filepath ---" | log
    echo_ansi "Info|[DRY RUN] --- $filepath ---"
    dry_run_report
    _restore_lang_state
    return 0
  fi

  determine_track_order
  map_default_tracks
  set_title_and_exit_if_nothing_removed
  remux_video
  set_perms_and_owner
  replace_original_video

  # Trigger rescan for this specific file if matched
  if [ "$striptracks_matched" = "true" ] && [ -n "$striptracks_rescan_id" ]; then
    rescan || true
  fi

  _restore_lang_state
}
function watch_directory {
  # Monitor directory for new/changed video files and process them

  local dir="$1"

  if [ ! -d "$dir" ]; then
    local message="Error|Directory not found: $dir"
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 1
  fi

  local message="Info|Entering watch mode on: $dir (settle delay: ${striptracks_watch_delay}s, cache refresh: ${striptracks_cache_refresh}m)"
  echo "$message" | log
  echo_ansi "$message"

  # Graceful shutdown on signals
  trap 'echo "Info|Watch mode interrupted" | log; echo_ansi "Info|Watch mode interrupted"; end_script 0' INT TERM

  # Background cache refresh timer
  # Writes directly to existing cache files so the parent process sees updated data.
  if [ -n "$striptracks_radarr_cache" ] || [ -n "$striptracks_sonarr_cache" ]; then
    (
      while true; do
        sleep "${striptracks_cache_refresh}m"
        echo "Info|Refreshing API cache" | log
        if [ -n "$striptracks_radarr_api_url" ] && [ -n "$striptracks_radarr_cache" ]; then
          set_api_context radarr
          call_api 1 "Getting movie list." "GET" "movie"
          if [ $? -eq 0 ] && [ -n "$striptracks_result" ]; then
            echo "$striptracks_result" > "$striptracks_radarr_cache"
            unset striptracks_result
          fi
        fi
        if [ -n "$striptracks_sonarr_api_url" ] && [ -n "$striptracks_sonarr_cache" ]; then
          set_api_context sonarr
          call_api 1 "Getting series list." "GET" "series"
          if [ $? -eq 0 ] && [ -n "$striptracks_result" ]; then
            echo "$striptracks_result" > "$striptracks_sonarr_cache"
            unset striptracks_result
          fi
        fi
      done
    ) &
    local cache_refresh_pid=$!
  fi

  # Process substitution keeps the while loop in the current shell so counter
  # increments and record_processed writes are not lost in a pipe subshell.
  while read -r filepath; do
    if is_video_file "$filepath"; then
      echo "Info|Detected new file: $filepath (waiting ${striptracks_watch_delay}s)" | log
      echo_ansi "Info|Detected new file: $(basename "$filepath")"
      sleep "$striptracks_watch_delay"

      # Re-check file exists (may have been moved during settle)
      if [ ! -f "$filepath" ]; then
        echo "Warn|File no longer exists after settle delay: $filepath" | log
        continue
      fi

      # Skip if already processed
      if is_already_processed "$filepath"; then
        [ $striptracks_debug -ge 1 ] && echo "Debug|Skipping already-processed: $filepath" | log
        continue
      fi

      striptracks_file_count=$((striptracks_file_count + 1))
      (
        process_single_file "$filepath"
      )
      local return=$?
      if [ $return -ne 0 ]; then
        striptracks_error_count=$((striptracks_error_count + 1))
        echo "Warn|Error processing: $filepath (exit code: $return)" | log
      else
        if [ "$striptracks_dry_run" != "true" ]; then
          local newfile="${filepath%.*}.mkv"
          record_processed "$newfile"
        fi
      fi
    fi
  done < <(inotifywait -m -r -e close_write,moved_to --format '%w%f' "$dir" 2>/dev/null)

  # Clean up background refresh
  [ -n "$cache_refresh_pid" ] && kill "$cache_refresh_pid" 2>/dev/null
}
function process_directory {
  # Recursively process all video files in a directory

  local dir="$1"

  if [ ! -d "$dir" ]; then
    local message="Error|Directory not found: $dir"
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 1
  fi

  local message="Info|Scanning directory: $dir (extensions: $striptracks_extensions)"
  echo "$message" | log
  echo_ansi "$message"

  # Build find expression from extensions list
  local -a find_args=()
  local first=true
  IFS=',' read -ra exts <<< "$striptracks_extensions"
  for ext in "${exts[@]}"; do
    if $first; then
      find_args+=(-iname "*.${ext}")
      first=false
    else
      find_args+=(-o -name "*.${ext}")
    fi
  done

  # Build exclude expressions
  local -a exclude_args=()
  if [ -n "$striptracks_excludes" ]; then
    IFS=',' read -ra patterns <<< "$striptracks_excludes"
    for pattern in "${patterns[@]}"; do
      exclude_args+=(-not -path "$pattern")
    done
    [ $striptracks_debug -ge 1 ] && echo "Debug|Excluding patterns: $striptracks_excludes" | log
  fi

  # Count total files for progress reporting
  export striptracks_file_total=$(find "$dir" -type f \( "${find_args[@]}" \) "${exclude_args[@]}" -print0 2>/dev/null | tr -dc '\0' | wc -c)
  local message="Info|Found $striptracks_file_total video files to process"
  echo "$message" | log
  echo_ansi "$message"

  while IFS= read -r -d '' file; do
    # Skip already-processed files
    if is_already_processed "$file"; then
      striptracks_skip_count=$((striptracks_skip_count + 1))
      [ $striptracks_debug -ge 1 ] && echo "Debug|Skipping already-processed: $file" | log
      continue
    fi

    striptracks_file_count=$((striptracks_file_count + 1))
    # Subshell contains end_script/exit calls so one file can't kill the batch
    (
      process_single_file "$file"
    )
    local return=$?
    if [ $return -ne 0 ]; then
      striptracks_error_count=$((striptracks_error_count + 1))
      echo "Warn|Error processing: $file (exit code: $return)" | log
    else
      # Record in state file (must be in parent, not subshell). Skip in dry-run.
      if [ "$striptracks_dry_run" != "true" ]; then
        local newfile="${file%.*}.mkv"
        record_processed "$newfile"
      fi
    fi
  done < <(find "$dir" -type f \( "${find_args[@]}" \) "${exclude_args[@]}" -print0 | sort -z)
}
