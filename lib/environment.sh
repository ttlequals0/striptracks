#!/bin/bash
# striptracks - Environment
# Binary checks, API context switching, and standalone variable initialization.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function check_required_binaries {
  for striptracks_bin in mkvmerge mkvpropedit jq; do
    if ! command -v "$striptracks_bin" &>/dev/null; then
      local message="Error|$striptracks_bin is required by this script"
      echo "$message" | log
      echo_ansi "$message" >&2
      end_script 4
    fi
  done
}
function set_api_context {
  # Switch API context to radarr or sonarr

  local api_type="$1" # 'radarr' or 'sonarr'
  if [ "$api_type" = "radarr" ]; then
    export striptracks_api_url="$striptracks_radarr_api_url"
    export striptracks_apikey="$striptracks_radarr_apikey"
    export striptracks_type="radarr"
    export striptracks_arr_version="$striptracks_radarr_version"
  elif [ "$api_type" = "sonarr" ]; then
    export striptracks_api_url="$striptracks_sonarr_api_url"
    export striptracks_apikey="$striptracks_sonarr_apikey"
    export striptracks_type="sonarr"
    export striptracks_arr_version="$striptracks_sonarr_version"
  fi
}
function check_watch_dependencies {
  # Verify inotifywait is available for watch mode
  if [ "$striptracks_run_mode" = "watch" ]; then
    if ! command -v inotifywait &>/dev/null; then
      local message="Error|Watch mode requires inotifywait (install inotify-tools package)"
      echo "$message" | log
      echo_ansi "$message" >&2
      end_script 4
    fi
  fi
}
function run_test_mode {
  # Validate configuration and report status

  echo_ansi "Info|=== Configuration Test ==="

  # Report binaries
  for bin in mkvmerge mkvpropedit jq curl inotifywait; do
    if command -v "$bin" &>/dev/null; then
      local ver=$("$bin" --version 2>&1 | head -1)
      echo_ansi "Info|  $bin: $ver"
    else
      echo_ansi "Warn|  $bin: not found"
    fi
  done

  # Report API connections
  if [ -n "$striptracks_radarr_api_url" ]; then
    echo_ansi "Info|  Radarr: v${striptracks_radarr_version} at $striptracks_radarr_url"
  else
    echo_ansi "Info|  Radarr: not configured"
  fi
  if [ -n "$striptracks_sonarr_api_url" ]; then
    echo_ansi "Info|  Sonarr: v${striptracks_sonarr_version} at $striptracks_sonarr_url"
  else
    echo_ansi "Info|  Sonarr: not configured"
  fi

  # Report cached library counts
  [ -n "$striptracks_radarr_cache" ] && echo_ansi "Info|  Radarr movies: $(jq 'length' "$striptracks_radarr_cache")"
  [ -n "$striptracks_sonarr_cache" ] && echo_ansi "Info|  Sonarr series: $(jq 'length' "$striptracks_sonarr_cache")"

  # Report directory info if specified
  if [ -n "$striptracks_dir" ] && [ -d "$striptracks_dir" ]; then
    local count=$(find "$striptracks_dir" -type f \( -name "*.mkv" -o -name "*.mp4" -o -name "*.avi" \) 2>/dev/null | wc -l)
    echo_ansi "Info|  Video files in $striptracks_dir: $count (approx)"
  fi

  # Report settings
  echo_ansi "Info|  Audio: ${striptracks_audiokeep:-auto-detect}"
  echo_ansi "Info|  Subs: ${striptracks_subskeep:-strip all}"
  echo_ansi "Info|  Dry run: $striptracks_dry_run"
  echo_ansi "Info|  State file: ${striptracks_state_file:-disabled}"
  echo_ansi "Info|  Extensions: $striptracks_extensions"

  echo_ansi "Info|=== Test Complete ==="
}

function initialize_standalone_variables {
  # Set up mode and API configuration

  if [ -n "$striptracks_dir" ]; then
    export striptracks_mode="directory"
  else
    export striptracks_mode="file"
    export striptracks_title="$(basename "$striptracks_video" ".${striptracks_video##*.}")"
    export striptracks_newvideo="${striptracks_video%.*}.mkv"
  fi

  # Configure Radarr API
  if [ -n "$striptracks_radarr_url" ] && [ -n "$striptracks_radarr_apikey" ]; then
    export striptracks_radarr_api_url="${striptracks_radarr_url%/}/api/v3"
    [ $striptracks_debug -ge 1 ] && echo "Debug|Validating Radarr API at $striptracks_radarr_api_url" | log
    set_api_context radarr
    if get_version; then
      export striptracks_radarr_version="$(echo $striptracks_result | jq -crM .version)"
      echo "Info|Connected to Radarr v${striptracks_radarr_version}" | log
    else
      echo "Warn|Unable to connect to Radarr API at $striptracks_radarr_url" | log
      unset striptracks_radarr_api_url
    fi
  fi

  # Configure Sonarr API
  if [ -n "$striptracks_sonarr_url" ] && [ -n "$striptracks_sonarr_apikey" ]; then
    export striptracks_sonarr_api_url="${striptracks_sonarr_url%/}/api/v3"
    [ $striptracks_debug -ge 1 ] && echo "Debug|Validating Sonarr API at $striptracks_sonarr_api_url" | log
    set_api_context sonarr
    if get_version; then
      export striptracks_sonarr_version="$(echo $striptracks_result | jq -crM .version)"
      echo "Info|Connected to Sonarr v${striptracks_sonarr_version}" | log
    else
      echo "Warn|Unable to connect to Sonarr API at $striptracks_sonarr_url" | log
      unset striptracks_sonarr_api_url
    fi
  fi

  # Resolve --original-language to ISO code
  if [ -n "$striptracks_original_language" ]; then
    export striptracks_originalLangCode="$(resolve_lang_to_iso "$striptracks_original_language")"
    if [ -z "$striptracks_originalLangCode" ]; then
      echo "Warn|Original language '$striptracks_original_language' not found in ISO code map" | log
    else
      [ $striptracks_debug -ge 1 ] && echo "Debug|Original language '$striptracks_original_language' mapped to '$striptracks_originalLangCode'" | log
    fi
  fi

  # Cache media libraries for directory mode
  if [ "$striptracks_mode" = "directory" ]; then
    cache_media_libraries
  fi
}
