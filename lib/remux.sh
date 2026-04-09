#!/bin/bash
# striptracks - Remux
# MKV command execution, video remuxing, file permissions, and rescan triggering.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function rescan {
  # Initiate Rescan request

  echo "Info|Calling ${striptracks_type^} API to rescan ${striptracks_video_type}" | log
  call_api 0 "Forcing rescan of $striptracks_video_type '$striptracks_rescan_id'." "POST" "command" "{\"name\":\"$striptracks_rescan_api\",\"${striptracks_video_type}Id\":$striptracks_rescan_id}"
  export striptracks_jobid="$(echo $striptracks_result | jq -crM '.id?')"
  [ "$striptracks_jobid" != "null" ] && [ "$striptracks_jobid" != "" ]
  return
}
function check_job {
  # Check result of command job

  # Exit codes:
  #  0 - success
  #  1 - queued
  #  2 - failed
  #  3 - loop timed out
  # 10 - curl error

  local jobid="$1" # Job ID to check

  local i
  for ((i=1; i <= 15; i++)); do
    call_api 0 "Checking job $jobid completion." "GET" "command/$jobid"
    local api_return=$?; [ $api_return -ne 0 ] && {
      local return=10
      break
    }

    # Job status checks
    local json_test="$(echo $striptracks_result | jq -crM '.status?')"
    case "$json_test" in
      completed) local return=0; break ;;
      failed) local return=2; break ;;
      queued) local return=3; break ;;
      *)
        # It may have timed out, so let's wait a second
        [ $striptracks_debug -ge 1 ] && echo "Debug|Job not done. Waiting 1 second." | log
        local return=3
        sleep 1
      ;;
    esac
  done
  return $return
}
function escape_string {
  local input="$1" # Input string to escape

  # Escape backslashes, double quotes, and dollar signs
  # shellcheck disable=SC2001
  local output="$(echo "$input" | sed -e 's/[`"\\$]/\\&/g')"
  echo "$output"
}
function execute_mkv_command {
  # Execute mkvmerge or mkvpropedit command

  local action="$1"  # Action being performed (for logging purposes)
  local command="$2" # Full mkvmerge or mkvpropedit command to execute
  local -a mkv_args=() # Use array instead of string for safer argument passing

  # Process remaining data values
  shift 2
  while (( "$#" )); do
    mkv_args+=("$1")
    shift
  done

  [ $striptracks_debug -ge 1 ] && echo "Debug|Executing: $command ${mkv_args[*]}" | log
  local shortcommand="$(echo $command | sed -E 's/(.+ )?(\/[^ ]+) .*$/\2/')"
  shortcommand=$(basename "$shortcommand")
  unset striptracks_mkvresult
  # This must be a declare statement to avoid the 'Argument list too long' error with some large returned JSON (see issue #104)
  declare -g striptracks_mkvresult
  striptracks_mkvresult=$($command "${mkv_args[@]}")
  local return=$?
  [ $striptracks_debug -ge 1 ] && echo "Debug|$shortcommand returned ${#striptracks_mkvresult} bytes" | log
  [ $striptracks_debug -ge 2 ] && [ ${#striptracks_mkvresult} -ne 0 ] && echo "$shortcommand returned: $striptracks_mkvresult" | awk '{print "Debug|"$0}' | log
  case $return in
    1)
      local message=$(echo -e "[$return] Warning when $action.\n$shortcommand returned: $(echo "$striptracks_mkvresult" | jq -RcrM '. as $raw | try ($raw | fromjson | .warnings[]) catch $raw')" | awk '{print "Warn|"$0}')
      echo "$message" | log
    ;;
    2)
      local message=$(echo -e "[$return] Error when $action.\n$shortcommand returned: $(echo "$striptracks_mkvresult" | jq -RcrM '. as $raw | try ($raw | fromjson | .errors[]) catch $raw')" | awk '{print "Error|"$0}')
      echo "$message" | log
      echo_ansi "$message" >&2
      end_script 13
    ;;
  esac
  # Check for unsupported container
  if [ "$(echo "$striptracks_mkvresult" | jq -crM '.container.supported')" = "false" ]; then
    local message="Error|Video format is unsupported. Unable to continue. $shortcommand returned container info: $(echo $striptracks_mkvresult | jq -crM .container)"
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 9
  fi
  return $return
}
function remux_video {
  # Execute MKVmerge to remux video

  # Build argument with kept audio tracks for MKVmerge
  local audioarg=$(echo "$striptracks_json_processed" | jq -crM '.tracks | map(select(.type == "audio" and .striptracks_keep) | .id) | join(",")')
  local audioarg="-a $audioarg"

  # Build argument with kept subtitles tracks for MKVmerge, or remove all subtitles
  local subsarg=$(echo "$striptracks_json_processed" | jq -crM '.tracks | map(select(.type == "subtitles" and .striptracks_keep) | .id) | join(",")')
  if [ ${#subsarg} -ne 0 ]; then
    local subsarg="-s $subsarg"
  else
    local subsarg="-S"
  fi

  # Build argument for track reorder option for MKVmerge
  if [ ${#striptracks_neworder} -ne 0 ]; then
    export striptracks_neworder="--track-order $striptracks_neworder"
  fi

  # Execute MKVmerge (remux then rename, see issue #46)
  local mkvcommand="$striptracks_nice /usr/bin/mkvmerge"
  execute_mkv_command "remuxing video" "$mkvcommand" -o "$striptracks_tempvideo" -q --title "$(escape_string "$striptracks_title")" $audioarg $subsarg $striptracks_mkvmerge_default_args $striptracks_neworder "$striptracks_video"

  # Check for non-empty file
  if [ ! -s "$striptracks_tempvideo" ]; then
    local message="Error|Unable to locate or invalid remuxed file: '$striptracks_tempvideo'.  Halting."
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 10
  fi
}
function set_perms_and_owner {
  # Set permissions and owner of the remuxed video

  # Check that the script is running as root
  if [ "$(id -u)" -eq 0 ]; then
    # Set owner
    [ $striptracks_debug -ge 1 ] && echo "Debug|Changing owner of file '$striptracks_tempvideo'" | log
    local result
    result=$(chown --reference="$striptracks_video" "$striptracks_tempvideo")
    local return=$?; [ $return -ne 0 ] && {
      local message=$(echo -e "[$return] Error when changing owner of file: '$striptracks_tempvideo'\nchown returned: $result" | awk '{print "Error|"$0}')
      echo "$message" | log
      echo_ansi "$message" >&2
      change_exit_status 15
    }
  else
    # Unable to change owner when not running as root
    [ $striptracks_debug -ge 1 ] && echo "Debug|Unable to change owner of file when running as user '$(id -un)'" | log
  fi
  # Set permissions
  local result
  result=$(chmod --reference="$striptracks_video" "$striptracks_tempvideo")
  local return=$?; [ $return -ne 0 ] && {
    local message=$(echo -e "[$return] Error when changing permissions of file: '$striptracks_tempvideo'\nchmod returned: $result" | awk '{print "Error|"$0}')
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 15
  }
}
function replace_original_video {
  # Replace original video with remuxed video

  # Check temp file still exists before deleting original
  if [ ! -f "$striptracks_tempvideo" ]; then
    local message="Error|Temporary remuxed file not found: '$striptracks_tempvideo'. Halting."
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 10
  fi

  [ $striptracks_debug -ge 1 ] && echo "Debug|Deleting: '$striptracks_video'" | log
  local result
  result=$(rm "$striptracks_video")
  local return=$?; [ $return -ne 0 ] && {
    local message=$(echo -e "[$return] Error when deleting video: '$striptracks_video'\nrm returned: $result" | awk '{print "Error|"$0}')
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 16
  }

  # Rename temporary video to final name
  [ $striptracks_debug -ge 1 ] && echo "Debug|Renaming '$striptracks_tempvideo' to '$striptracks_newvideo'" | log
  local result
  result=$(mv -f "$striptracks_tempvideo" "$striptracks_newvideo")
  local return=$?; [ $return -ne 0 ] && {
    local message=$(echo -e "[$return] Unable to rename: '$striptracks_tempvideo' to: '$striptracks_newvideo'\nmv returned: $result" | awk '{print "Error|"$0}')
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 6
  }

  # Log new file size
  # shellcheck disable=SC2046
  local filesize=$(stat -c %s "${striptracks_newvideo}" | numfmt --to iec --format "%.3f")
  local message="Info|New size: $filesize"
  echo "$message" | log
}
