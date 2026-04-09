#!/bin/bash
# striptracks - CLI
# Usage display, variable initialization, command-line parsing, and exit handling.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function _set_priority {
  local priority="$1"
  case "$priority" in
    idle) export striptracks_nice="ionice -c 3 nice -n 19" ;;
    low) export striptracks_nice="ionice -c 2 -n 7 nice -n 19" ;;
    medium) export striptracks_nice="ionice -c 2 -n 4 nice -n 10" ;;
    high) export striptracks_nice="ionice -c 2 -n 0 nice -n 0" ;;
  esac
}

function usage {
  usage="Try '$striptracks_script --help' for more information."
  echo "$usage" >&2
}
function long_usage {
  usage="$striptracks_script   Version: $striptracks_ver
Standalone video track stripping tool.
Recursively processes directories of video files, removing unwanted audio and
subtitle tracks using mkvmerge.

Source: https://github.com/TheCaptain989/radarr-striptracks

Usage:
  $striptracks_script {-D|--dir} <directory> [{-a|--audio} <audio_languages>] [{-s|--subs} <subtitle_languages>]
  $striptracks_script {-f|--file} <video_file> {-a|--audio} <audio_languages> [{-s|--subs} <subtitle_languages>]
      [--dry-run]
      [--reorder]
      [--set-default-audio <audio_languages>[{+|-}modifiers][=name]]
      [--set-default-subs <subtitle_languages>[{+|-}modifiers][=name]]
      [--extensions <ext_list>]
      [--original-language <name>]
      [--radarr-url <url>] [--radarr-api-key <key>]
      [--sonarr-url <url>] [--sonarr-api-key <key>]
      [{-l|--log} <log_file>]
      [{-p|--priority} {idle|low|medium|high}]
      [{-d|--debug} [<level>]]
      [--no-ansi]

  Options can also be set via environment variables (see below).
  Command-line arguments override environment variables.

Options and Arguments:
  -D, --dir <directory>
                  Process all video files in directory recursively.

  -f, --file <video_file>
                  Process a single video file.

  -a, --audio <audio_languages>[{+|-}modifiers][=name]
                  Audio languages to keep.
                  ISO639-2 code(s) prefixed with a colon \`:\`
                  Multiple codes may be concatenated.
                  If omitted and API is configured, auto-detected from quality profile.

  -s, --subs <subtitle_languages>[{+|-}modifiers][=name]
                  Subtitle languages to keep.
                  ISO639-2 code(s) prefixed with a colon \`:\`
                  Default: strip all embedded subtitles.

      --test      Validate configuration, report API connections, and exit
                  without processing any files.
                  Env: STRIPTRACKS_TEST

      --mode run|wait|watch
                  Run mode. 'run' processes and exits (default).
                  'wait' processes then waits for Enter before exiting.
                  'watch' processes then monitors for new files.
                  Env: STRIPTRACKS_MODE

      --watch-delay <seconds>
                  Seconds to wait after detecting a new file before processing
                  (allows file writes to complete). Env: STRIPTRACKS_WATCH_DELAY
                  [default: 60]

      --cache-refresh <minutes>
                  How often to refresh the Radarr/Sonarr library cache in watch
                  mode. Env: STRIPTRACKS_CACHE_REFRESH  [default: 30]

      --dry-run   Preview mode. Show what would be changed without remuxing.

      --reorder   Reorder audio and subtitles tracks to match language code order.

      --extensions <ext_list>
                  Comma-separated list of video file extensions to process.
                  [default: mkv,mp4,avi,wmv,flv,mov,webm]

      --state-file <path>
                  Path to state file for tracking processed files.
                  Env: STRIPTRACKS_STATE_FILE
                  [default: /config/striptracks.state]

      --no-state  Disable state tracking (reprocess all files)

      --exclude <pattern>
                  Glob pattern to exclude from processing.
                  May be specified multiple times.
                  Env: STRIPTRACKS_EXCLUDE (comma-separated)

      --original-language <name>
                  Specify the original language name for :org code resolution
                  without requiring API access. (e.g., Japanese, French)

      --radarr-url <url>
                  Radarr API base URL (e.g., http://radarr:7878)
                  Env: RADARR_URL

      --radarr-api-key <key>
                  Radarr API key. Env: RADARR_API_KEY

      --sonarr-url <url>
                  Sonarr API base URL (e.g., http://sonarr:8989)
                  Env: SONARR_URL

      --sonarr-api-key <key>
                  Sonarr API key. Env: SONARR_API_KEY

      --set-default-audio <audio_languages>[{+|-}modifier(s)][=name]
                  Set the default audio track to the first track that matches.

      --set-default-subs <subtitle_languages>[{+|-}modifier(s)][=name]
                  Set the default subtitles track to the first track that matches.

  -l, --log <log_file>
                  Log filename. Env: STRIPTRACKS_LOG
                  [default: /config/logs/striptracks.log]

  -p, --priority idle|low|medium|high
                  CPU and I/O process priority for mkvmerge.
                  Env: STRIPTRACKS_PRIORITY  [default: medium]

  -d, --debug [<level>]
                  Enable debug logging. Level 1-3. [default: 1]

      --no-ansi   Force disable ANSI color codes in terminal output.

      --help      Display this help and exit.

      --version   Display script version and exit.

Environment Variables:
  STRIPTRACKS_DIR         Directory to process recursively
  STRIPTRACKS_AUDIO       Audio languages to keep (e.g., :eng:und)
  STRIPTRACKS_SUBS        Subtitle languages to keep (empty = strip all)
  STRIPTRACKS_TEST        Set 'true' to validate config and exit
  STRIPTRACKS_MODE        Run mode: run, wait, or watch
  STRIPTRACKS_WATCH_DELAY Settle delay in seconds for watch mode (default: 60)
  STRIPTRACKS_CACHE_REFRESH Cache refresh interval in minutes for watch mode (default: 30)
  STRIPTRACKS_DRY_RUN     Set to 'true' for preview mode
  STRIPTRACKS_EXTENSIONS  Comma-separated file extensions (default: mkv,mp4,avi,wmv,flv,mov,webm)
  STRIPTRACKS_STATE_FILE  Path to processed-files state file
  STRIPTRACKS_EXCLUDE     Comma-separated glob patterns to exclude
  STRIPTRACKS_REORDER     Set to 'true' to reorder tracks
  STRIPTRACKS_DEBUG       Debug level (0-3)
  STRIPTRACKS_LOG         Log file path
  STRIPTRACKS_PRIORITY    Process priority (idle/low/medium/high)
  RADARR_URL              Radarr API base URL
  RADARR_API_KEY          Radarr API key
  SONARR_URL              Sonarr API base URL
  SONARR_API_KEY          Sonarr API key

Language modifiers are prefixed with plus \`+\` or minus \`-\` and may be \`f\` or \`d\` which
selects tracks with or without Forced or Default flags set respectively, or a number which specifies
the maximum tracks to keep.

The name string is used as a case-insensitive match against the track name.

Examples:
  $striptracks_script -D /movies -a :eng:und -s :eng
                  # Process all videos in /movies, keep English/Unknown audio
                  # and English subtitles

  $striptracks_script -D /movies -a :eng:und
                  # Keep English/Unknown audio, strip all embedded subtitles

  $striptracks_script -D /movies --dry-run -a :eng
                  # Preview what would be changed without remuxing

  $striptracks_script -f movie.mkv -a :eng:jpn -s :eng --reorder
                  # Single file, keep English and Japanese audio, reorder

  $striptracks_script -D /anime -a :eng:org -s :eng --original-language Japanese
                  # Keep English and Original (Japanese) audio
"
  echo "$usage"
}
function initialize_variables {
  # Initialize global variables

  export striptracks_script=$(basename "$0")
  export striptracks_ver="{{VERSION}}"
  export striptracks_pid=$$
  export striptracks_debug="${STRIPTRACKS_DEBUG:-0}"
  export striptracks_nice="ionice -c 2 -n 4 nice -n 10"
  export striptracks_extensions="${STRIPTRACKS_EXTENSIONS:-mkv,mp4,avi,wmv,flv,mov,webm}"
  export striptracks_excludes="${STRIPTRACKS_EXCLUDE:-}"
  export striptracks_state_file="${STRIPTRACKS_STATE_FILE:-/config/striptracks.state}"
  export striptracks_test="${STRIPTRACKS_TEST:-false}"
  export striptracks_run_mode="${STRIPTRACKS_MODE:-run}"
  export striptracks_watch_delay="${STRIPTRACKS_WATCH_DELAY:-60}"
  export striptracks_cache_refresh="${STRIPTRACKS_CACHE_REFRESH:-30}"
  export striptracks_dry_run="${STRIPTRACKS_DRY_RUN:-false}"
  export striptracks_log="${STRIPTRACKS_LOG:-/config/logs/striptracks.log}"
  export striptracks_maxlogsize=512000
  export striptracks_maxlog=4
  export striptracks_file_count=0
  export striptracks_skip_count=0
  export striptracks_error_count=0

  # Read API config from environment
  export striptracks_radarr_url="${RADARR_URL:-}"
  export striptracks_radarr_apikey="${RADARR_API_KEY:-}"
  export striptracks_sonarr_url="${SONARR_URL:-}"
  export striptracks_sonarr_apikey="${SONARR_API_KEY:-}"

  # Read language config from environment
  [ -n "$STRIPTRACKS_AUDIO" ] && export striptracks_audiokeep="$STRIPTRACKS_AUDIO"
  [ -n "$STRIPTRACKS_SUBS" ] && export striptracks_subskeep="$STRIPTRACKS_SUBS"
  [ -n "$STRIPTRACKS_DIR" ] && export striptracks_dir="$STRIPTRACKS_DIR"
  [ "$STRIPTRACKS_REORDER" = "true" ] && export striptracks_reorder="true"

  # Read priority from environment
  if [ -n "$STRIPTRACKS_PRIORITY" ]; then
    _set_priority "$STRIPTRACKS_PRIORITY"
  fi

  # shellcheck disable=SC2089
  export striptracks_isocodemap='{"languages":[{"language":{"name":"Afrikaans","iso639-2":["afr"]}},{"language":{"name":"Albanian","iso639-2":["sqi","alb"]}},{"language":{"name":"Any","iso639-2":["any"]}},{"language":{"name":"Arabic","iso639-2":["ara"]}},{"language":{"name":"Bengali","iso639-2":["ben"]}},{"language":{"name":"Bosnian","iso639-2":["bos"]}},{"language":{"name":"Bulgarian","iso639-2":["bul"]}},{"language":{"name":"Catalan","iso639-2":["cat"]}},{"language":{"name":"Chinese","iso639-2":["zho","chi"]}},{"language":{"name":"Croatian","iso639-2":["hrv"]}},{"language":{"name":"Czech","iso639-2":["ces","cze"]}},{"language":{"name":"Danish","iso639-2":["dan"]}},{"language":{"name":"Dutch","iso639-2":["nld","dut"]}},{"language":{"name":"English","iso639-2":["eng"]}},{"language":{"name":"Estonian","iso639-2":["est"]}},{"language":{"name":"Finnish","iso639-2":["fin"]}},{"language":{"name":"Flemish","iso639-2":["nld","dut"]}},{"language":{"name":"French","iso639-2":["fra","fre"]}},{"language":{"name":"Georgian","iso639-2":["kat","geo"]}},{"language":{"name":"German","iso639-2":["deu","ger"]}},{"language":{"name":"Greek","iso639-2":["ell","gre"]}},{"language":{"name":"Hebrew","iso639-2":["heb"]}},{"language":{"name":"Hindi","iso639-2":["hin"]}},{"language":{"name":"Hungarian","iso639-2":["hun"]}},{"language":{"name":"Icelandic","iso639-2":["isl","ice"]}},{"language":{"name":"Indonesian","iso639-2":["ind"]}},{"language":{"name":"Italian","iso639-2":["ita"]}},{"language":{"name":"Japanese","iso639-2":["jpn"]}},{"language":{"name":"Kannada","iso639-2":["kan"]}},{"language":{"name":"Korean","iso639-2":["kor"]}},{"language":{"name":"Latvian","iso639-2":["lav"]}},{"language":{"name":"Lithuanian","iso639-2":["lit"]}},{"language":{"name":"Macedonian","iso639-2":["mac","mkd"]}},{"language":{"name":"Malayalam","iso639-2":["mal"]}},{"language":{"name":"Marathi","iso639-2":["mar"]}},{"language":{"name":"Mongolian","iso639-2":["mon"]}},{"language":{"name":"Norwegian","iso639-2":["nno","nob","nor"]}},{"language":{"name":"Persian","iso639-2":["fas","per"]}},{"language":{"name":"Polish","iso639-2":["pol"]}},{"language":{"name":"Portuguese","iso639-2":["por"]}},{"language":{"name":"Portuguese (Brazil)","iso639-2":["por"]}},{"language":{"name":"Romanian","iso639-2":["rum","ron"]}},{"language":{"name":"Romansh","iso639-2":["roh"]}},{"language":{"name":"Russian","iso639-2":["rus"]}},{"language":{"name":"Serbian","iso639-2":["srp"]}},{"language":{"name":"Slovak","iso639-2":["slk","slo"]}},{"language":{"name":"Slovenian","iso639-2":["slv"]}},{"language":{"name":"Spanish","iso639-2":["spa"]}},{"language":{"name":"Spanish (Latino)","iso639-2":["spa"]}},{"language":{"name":"Swedish","iso639-2":["swe"]}},{"language":{"name":"Tagalog","iso639-2":["tgl"]}},{"language":{"name":"Tamil","iso639-2":["tam"]}},{"language":{"name":"Telugu","iso639-2":["tel"]}},{"language":{"name":"Thai","iso639-2":["tha"]}},{"language":{"name":"Turkish","iso639-2":["tur"]}},{"language":{"name":"Ukrainian","iso639-2":["ukr"]}},{"language":{"name":"Unknown","iso639-2":["und"]}},{"language":{"name":"Urdu","iso639-2":["urd"]}},{"language":{"name":"Vietnamese","iso639-2":["vie"]}}]}'
}
function process_command_line {
  # Process arguments, either from the command line or from the environment variable

  # Log command-line arguments
  if [ $# -ne 0 ]; then
    export striptracks_prelogmessagedebug="Debug|Command line arguments are '$*'"
  fi

  # Check for environment variable arguments
  if [ -n "$STRIPTRACKS_ARGS" ]; then
    if [ $# -ne 0 ]; then
      export striptracks_prelogmessage="Warning|STRIPTRACKS_ARGS environment variable set but will be ignored because command line arguments were also specified."
    else
      export striptracks_prelogmessage="Info|Using settings from environment variable."
      eval set -- "$STRIPTRACKS_ARGS"
    fi
  fi

  # Process arguments
  unset pos_params
  while (( "$#" )); do
    case "$1" in
      -d|--debug )
        if [ -n "$2" ] && [ ${2:0:1} != "-" ] && [[ "$2" =~ ^[0-9]+$ ]]; then
          export striptracks_debug=$2
          shift 2
        else
          export striptracks_debug=1
          shift
        fi
      ;;
      -l|--log )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_log="$2"
        shift 2
      ;;
      --help )
        long_usage
        exit 0
      ;;
      --version )
        echo_ansi "${striptracks_script} ${striptracks_ver/{{VERSION\}\}/unknown}"
        exit 0
      ;;
      -f|--file )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
        export striptracks_video="$2"
        shift 2
      ;;
      -D|--dir )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 1
        fi
        export striptracks_dir="$2"
        shift 2
      ;;
      -a|--audio )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 2
        elif [[ "$2" != :* ]]; then
          echo_ansi "Error|Invalid option: $1 argument requires a colon." >&2
          usage
          exit 2
        fi
        export striptracks_audiokeep="$2"
        shift 2
      ;;
      -s|--subs|--subtitles )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 3
        elif [[ "$2" != :* ]]; then
          echo_ansi "Error|Invalid option: $1 argument requires a colon." >&2
          usage
          exit 3
        fi
        export striptracks_subskeep="$2"
        shift 2
      ;;
      -p|--priority )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        elif ! [[ "$2" =~ ^(idle|low|medium|high)$ ]]; then
          echo_ansi "Error|Invalid option: $1 argument must be idle, low, medium, or high." >&2
          usage
          exit 20
        fi
        _set_priority "$2"
        shift 2
      ;;
      --reorder )
        export striptracks_reorder="true"
        shift
      ;;
      --test )
        export striptracks_test="true"
        shift
      ;;
      --mode )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        elif ! [[ "$2" =~ ^(run|wait|watch)$ ]]; then
          echo_ansi "Error|Invalid option: $1 argument must be run, wait, or watch." >&2
          usage
          exit 20
        fi
        export striptracks_run_mode="$2"
        shift 2
      ;;
      --watch-delay )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_watch_delay="$2"
        shift 2
      ;;
      --cache-refresh )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_cache_refresh="$2"
        shift 2
      ;;
      --dry-run )
        export striptracks_dry_run="true"
        shift
      ;;
      --state-file )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_state_file="$2"
        shift 2
      ;;
      --no-state )
        export striptracks_state_file=""
        shift
      ;;
      --exclude )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        if [ -n "$striptracks_excludes" ]; then
          striptracks_excludes="$striptracks_excludes,$2"
        else
          striptracks_excludes="$2"
        fi
        shift 2
      ;;
      --no-ansi )
        export striptracks_noansi="true"
        shift
      ;;
      --extensions )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_extensions="$2"
        shift 2
      ;;
      --original-language )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_original_language="$2"
        shift 2
      ;;
      --radarr-url )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_radarr_url="$2"
        shift 2
      ;;
      --radarr-api-key )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_radarr_apikey="$2"
        shift 2
      ;;
      --sonarr-url )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_sonarr_url="$2"
        shift 2
      ;;
      --sonarr-api-key )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        fi
        export striptracks_sonarr_apikey="$2"
        shift 2
      ;;
      --set-default-audio )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        elif [[ "$2" != :* ]]; then
          echo_ansi "Error|Invalid option: $1 argument requires a colon." >&2
          usage
          exit 20
        fi
        export striptracks_default_audio="$2"
        shift 2
      ;;
      --set-default-subs|--set-default-subtitles )
        if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
          echo_ansi "Error|Invalid option: $1 requires an argument." >&2
          usage
          exit 20
        elif [[ "$2" != :* ]]; then
          echo_ansi "Error|Invalid option: $1 argument requires a colon." >&2
          usage
          exit 20
        fi
        export striptracks_default_subtitles="$2"
        shift 2
      ;;
      -*)
        echo_ansi "Error|Unknown option: $1" >&2
        usage
        exit 20
      ;;
      *)
        local pos_params="$pos_params $1"
        shift
      ;;
    esac
  done
  eval set -- "$pos_params"

  # Check for and assign positional arguments. Named override positional.
  if [ -n "$1" ]; then
    if [ -n "$striptracks_audiokeep" ]; then
      echo_ansi "Warning|Both positional and named arguments set for audio. Using $striptracks_audiokeep" >&2
    else
      export striptracks_audiokeep="$1"
    fi
  fi
  if [ -n "$2" ]; then
    if [ -n "$striptracks_subskeep" ]; then
      echo_ansi "Warning|Both positional and named arguments set for subtitles. Using $striptracks_subskeep" >&2
    else
      export striptracks_subskeep="$2"
    fi
  fi

  # Validate: need either -f or -D
  if [ "$striptracks_test" != "true" ] && [ -z "$striptracks_video" ] && [ -z "$striptracks_dir" ]; then
    echo_ansi "Error|Either --file or --dir must be specified." >&2
    usage
    exit 1
  fi
  if [ -n "$striptracks_video" ] && [ -n "$striptracks_dir" ]; then
    echo_ansi "Error|Cannot specify both --file and --dir." >&2
    usage
    exit 1
  fi

  # In single file mode, require --audio
  if [ "$striptracks_test" != "true" ] && [ -n "$striptracks_video" ] && [ -z "$striptracks_audiokeep" ]; then
    echo_ansi "Error|Single file mode requires the --audio option." >&2
    usage
    exit 2
  fi
}
function end_script {
  # Clean up temp files
  [ -n "$striptracks_radarr_cache" ] && rm -f "$striptracks_radarr_cache" 2>/dev/null
  [ -n "$striptracks_sonarr_cache" ] && rm -f "$striptracks_sonarr_cache" 2>/dev/null
  rm -f /tmp/striptracks_epfiles_*.json 2>/dev/null
  [ -n "$striptracks_tempvideo" ] && rm -f "$striptracks_tempvideo" 2>/dev/null

  local message="Info|Completed in $((SECONDS/60))m $((SECONDS%60))s"
  echo "$message" | log
  [ "$1" != "" ] && export striptracks_exitstatus=$1
  [ $striptracks_debug -ge 1 ] && echo "Debug|Exit code ${striptracks_exitstatus:-0}" | log
  exit ${striptracks_exitstatus:-0}
}
function change_exit_status {
  # Set exit status code, but only if it is not already set

  local exit_status="$1" # Exit status code to set
  if [ -z "$striptracks_exitstatus" ]; then
    export striptracks_exitstatus="$exit_status"
  fi
}
function trigger_rescan {
  # Fire-and-forget rescan after all processing (for single file mode)

  # In directory mode, rescans happen per-file inside process_single_file
  if [ "$striptracks_mode" = "directory" ]; then
    return
  fi

  # Only trigger if we matched a media item and have API access
  if [ "$striptracks_matched" = "true" ] && [ -n "$striptracks_rescan_id" ]; then
    rescan || {
      echo "Warn|Rescan trigger failed" | log
    }
  fi
}
