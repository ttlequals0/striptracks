#!/bin/bash
# shellcheck disable=SC1091

# Standalone video track stripping tool
# Recursively processes directories of video files, removing unwanted audio and subtitle tracks.
# Optionally integrates with Radarr/Sonarr APIs for language auto-detection and library rescanning.
#
# Forked from: https://github.com/TheCaptain989/radarr-striptracks
#
# Dependencies:
#  mkvmerge, mkvpropedit (from mkvtoolnix)
#  jq
#  curl (optional, for API integration)
#  bash 4+

# Exit codes:
#  0 - success
#  1 - no video file or directory specified
#  2 - no audio language specified
#  3 - no subtitles language specified
#  4 - mkvmerge, mkvpropedit, or jq not found
#  5 - input video file not found
#  6 - unable to rename temp video to MKV
#  9 - mkvmerge returned an unsupported container format
# 10 - remuxing completed, but no output file found
# 11 - source video had no audio tracks
# 12 - log file is not writable
# 13 - mkvmerge or mkvpropedit exited with an error
# 15 - could not set permissions and/or owner on new file
# 16 - could not delete the original file
# 17 - API error
# 20 - general error

# Determine script directory for module loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source modules in dependency order
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/cli.sh"
source "${SCRIPT_DIR}/lib/language.sh"
source "${SCRIPT_DIR}/lib/api.sh"
source "${SCRIPT_DIR}/lib/environment.sh"
source "${SCRIPT_DIR}/lib/media.sh"
source "${SCRIPT_DIR}/lib/tracks.sh"
source "${SCRIPT_DIR}/lib/remux.sh"
source "${SCRIPT_DIR}/lib/directory.sh"

### Main
function main {
  initialize_variables
  setup_ansi_colors
  process_command_line "$@"
  initialize_standalone_variables
  check_log
  check_required_binaries
  check_watch_dependencies
  log_first_debug_messages

  # Test mode: validate and exit
  if [ "$striptracks_test" = "true" ]; then
    run_test_mode
    end_script 0
  fi

  if [ "$striptracks_mode" = "directory" ]; then
    process_directory "$striptracks_dir"
  else
    process_single_file "$striptracks_video"
  fi

  trigger_rescan

  if [ "$striptracks_mode" = "directory" ]; then
    local message="Info|Directory processing complete. Processed: $striptracks_file_count/$striptracks_file_total, Skipped: $striptracks_skip_count, Errors: $striptracks_error_count"
    echo "$message" | log
    echo_ansi "$message"
  fi

  # Run mode handling
  case "$striptracks_run_mode" in
    wait)
      local message="Info|Processing complete. Press Enter to exit..."
      echo "$message" | log
      echo_ansi "$message"
      read -r
      ;;
    watch)
      if [ "$striptracks_mode" != "directory" ]; then
        local message="Error|Watch mode requires --dir"
        echo "$message" | log
        echo_ansi "$message" >&2
        end_script 20
      fi
      watch_directory "$striptracks_dir"
      ;;
  esac
}

# Do not execute if this script is being sourced from a test script
if ! [[ "${BASH_SOURCE[1]}" =~ test_.*\.sh$ ]]; then
  main "$@"
  end_script
fi
