#!/bin/bash
# striptracks - Logging
# ANSI color setup, log writing, debug output, and dry-run reporting.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function setup_ansi_colors {
  # Setup ANSI color codes and determine when to use them.
  # Colors should only be used when the script is writing to an interactive terminal.

  export ansi_red='\033[0;31m'
  export ansi_green='\033[0;32m'
  export ansi_yellow='\033[0;33m'
  export ansi_cyan='\033[0;36m'
  export ansi_nc='\033[0m' # No Color
}
function strip_ansi_codes {
  # Remove ANSI escape sequences from stdin (e.g., before writing to log files)
  sed -E 's/\x1B\[[0-9;]*[mK]//g'
}
function echo_ansi {
  # Apply ANSI colors for terminal output only.
  # Colors are based on the message prefix (Error|, Warn|, Debug|).

  local msg="$*"
  local prefix="${msg%%|*}"
  local color=""
  case "$prefix" in
    Error) color="$ansi_red" ;;
    Warn)  color="$ansi_yellow" ;;
    Debug) color="$ansi_cyan" ;;
  esac

  local use_color=false
  if [ -t 1 -a -t 2 ] && [ -z "$striptracks_noansi" ]; then
    use_color=true
  fi

  if $use_color && [ -n "$color" ]; then
    builtin echo -e "${color}${msg}${ansi_nc}"
  else
    builtin echo "$msg"
  fi
}
function log {(
  # Can still go over striptracks_maxlog if read line is too long
  # Must include whole function in subshell for read to work!

  while read -r; do
    # Ensure ANSI escape sequences are stripped from log output
    local line="$REPLY"
    line="$(printf '%s' "$line" | strip_ansi_codes)"

    # shellcheck disable=2046
    local formatted="$(date +"%Y-%m-%d %H:%M:%S.%1N")|[$striptracks_pid]$line"
    builtin echo "$formatted" >>"$striptracks_log" 2>/dev/null || true
    # Write to stderr for Docker log collection (stdout is consumed by the pipe)
    builtin echo "$formatted" >&2
    local filesize=$(stat -c %s "$striptracks_log" 2>/dev/null || echo 0)
    if [ $filesize -gt $striptracks_maxlogsize ]; then
      for i in $(seq $((striptracks_maxlog-1)) -1 0); do
        [ -f "${striptracks_log::-4}.$i.txt" ] && mv "${striptracks_log::-4}."{$i,$((i+1))}".txt"
      done
      [ -f "${striptracks_log::-4}.txt" ] && mv "${striptracks_log::-4}.txt" "${striptracks_log::-4}.0.txt"
      touch "$striptracks_log"
    fi
  done
)}
function check_log {
  # Create log directory if it doesn't exist
  local logdir="$(dirname "$striptracks_log")"
  if [ ! -d "$logdir" ]; then
    mkdir -p "$logdir" 2>/dev/null || {
      [ $striptracks_debug -ge 1 ] && echo_ansi "Debug|Cannot create log directory '$logdir'. Using log file in current directory."
      export striptracks_log=./striptracks.txt
    }
  fi

  # Create log file if it doesn't exist
  if [ ! -f "$striptracks_log" ]; then
    touch "$striptracks_log" 2>/dev/null || {
      echo_ansi "Warn|Cannot create log file '$striptracks_log'. Using current directory."
      export striptracks_log=./striptracks.txt
      touch "$striptracks_log"
    }
  fi

  # Check that the log file is writable
  if [ ! -w "$striptracks_log" ]; then
    echo_ansi "Error|Log file '$striptracks_log' is not writable or does not exist." >&2
    export striptracks_log=/dev/null
    change_exit_status 12
  fi
}
function log_first_debug_messages {
  # First log messages

  if [ $striptracks_debug -ge 1 ]; then
    local message="Debug|Running ${striptracks_script} version ${striptracks_ver/{{VERSION\}\}/unknown} in ${striptracks_mode} mode with debug logging level ${striptracks_debug}"
    echo "$message" | log
    echo_ansi "$message" >&2
    [ -n "$striptracks_radarr_url" ] && echo "Debug|Radarr API: $striptracks_radarr_url" | log
    [ -n "$striptracks_sonarr_url" ] && echo "Debug|Sonarr API: $striptracks_sonarr_url" | log
    echo "Debug|Audio: ${striptracks_audiokeep:-auto-detect}, Subs: ${striptracks_subskeep:-strip all}" | log
    echo "Debug|Extensions: $striptracks_extensions" | log
    [ "$striptracks_dry_run" = "true" ] && echo "Debug|DRY RUN MODE - no files will be modified" | log
  fi

  if [ -n "$striptracks_prelogmessagedebug" ]; then
    [ $striptracks_debug -ge 1 ] && echo "$striptracks_prelogmessagedebug" | log
  fi

  if [ -n "$striptracks_prelogmessage" ]; then
    echo "$striptracks_prelogmessage" | log
    [ $striptracks_debug -ge 1 ] && echo "Debug|STRIPTRACKS_ARGS: ${STRIPTRACKS_ARGS}" | log
  fi
}
function dry_run_report {
  # Print dry-run report for a single file

  echo "$striptracks_json_processed" | jq -crM '
    .tracks | group_by(.type) | map({
      type: .[0].type,
      tracks: map({
        action: (if .striptracks_keep then "KEEP" else "STRIP" end),
        id: .id,
        lang: .language,
        name: (.name // ""),
        forced: .forced,
        default: .default
      })
    }) | .[] |
    "  \(.type | ascii_upcase) tracks:",
    (.tracks[] | "    [\(.action)] Track \(.id): \(.lang)\(if .name != "" then " - \"\(.name)\"" else "" end)\(if .forced then " [forced]" else "" end)\(if .default then " [default]" else "" end)")
  ' | while read -r line; do
    echo "Info|[DRY RUN] $line" | log
    echo_ansi "Info|[DRY RUN] $line"
  done

  local strip_count=$(echo "$striptracks_json_processed" | jq -crM '.tracks | map(select(.striptracks_keep == false)) | length')
  local keep_count=$(echo "$striptracks_json_processed" | jq -crM '.tracks | map(select(.striptracks_keep)) | length')
  local message="Info|[DRY RUN] Would keep $keep_count tracks, remove $strip_count tracks"
  echo "$message" | log
  echo_ansi "$message"
}
