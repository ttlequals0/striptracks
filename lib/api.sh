#!/bin/bash
# striptracks - API
# Radarr/Sonarr API communication, version checks, profile and media queries.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function call_api {
  # Call the Radarr/Sonarr API

  local debug_add=$1 # Value added to debug level when evaluating for JSON debug output
  local message="$2" # Message to log
  local method="$3" # HTTP method to use (GET, POST, PUT, DELETE)
  local endpoint="$4" # API endpoint to call
  local -a curl_data_args=() # Use array instead of string for safer argument passing (see issue #118)

  # Process remaining data values
  shift 4
  while (( "$#" )); do
    case "$1" in
      "{"*|"["*)
        curl_data_args+=(--json "$1")
      ;;
      *=*)
        curl_data_args+=(--data-urlencode "$1")
      ;;
      *)
        curl_data_args+=(--data-raw "$1")
      ;;
    esac
    shift
  done

  local -a curl_args=(
    -s
    --fail-with-body
    -H "X-Api-Key: $striptracks_apikey"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
  )

  local url="$striptracks_api_url/$endpoint"
  local data_info=""
  [ ${#curl_data_args[@]} -gt 0 ] && data_info=" with data: ${curl_data_args[*]}"
  [ $striptracks_debug -ge 1 ] && echo "Debug|$message Calling ${striptracks_type^} API using $method and URL '$url'$data_info" | log
  # Special handling of GET method
  if [ "$method" = "GET" ]; then
    curl_args+=(-G)
  else
    curl_args+=(-X "$method")
  fi
  # Add data arguments and url to curl arguments array
  curl_args+=("${curl_data_args[@]}")
  curl_args+=(--url "$url")
  [ $striptracks_debug -ge 2 ] && echo "Debug|Executing: curl ${curl_args[*]}" | sed -E 's/(X-Api-Key: )[^ ]+/\1[REDACTED]/' | log
  unset striptracks_result
  # (See issue #104)
  declare -g striptracks_result

  striptracks_result=$(curl "${curl_args[@]}")
  local curl_return=$?
  if [ $curl_return -ne 0 ]; then
    local error_message="$(echo $striptracks_result | jq -jcM 'if type=="array" then map(.errorMessage) | join(", ") else (if has("title") then "[HTTP \(.status?)] \(.title) \(.errors?)" elif has("message") then .message else "Unknown JSON format." end) end')"
    local message=$(echo -e "[$curl_return] curl error when calling: \"$url\"$data_info\nWeb server returned: $error_message" | awk '{print "Error|"$0}')
    echo "$message" | log
    echo_ansi "$message" >&2
  fi

  # APIs can return A LOT of data, and it is not always needed for debugging
  [ $striptracks_debug -ge 2 ] && echo "Debug|API returned ${#striptracks_result} bytes." | log
  [ $striptracks_debug -ge $((2 + debug_add)) -a ${#striptracks_result} -gt 0 ] && echo "API returned: $striptracks_result" | awk '{print "Debug|"$0}' | log
  return $curl_return
}
function get_version {
  # Get Radarr/Sonarr version

  call_api 0 "Getting ${striptracks_type^} version." "GET" "system/status"
  local json_test="$(echo $striptracks_result | jq -crM '.version?')"
  [ "$json_test" != "null" ] && [ "$json_test" != "" ]
  return
}
function get_video_info {
  # Get video information

  call_api 0 "Getting video information for $striptracks_video_api '$striptracks_video_id'." "GET" "$striptracks_video_api/$striptracks_video_id"
  local json_test="$(echo $striptracks_result | jq -crM '.hasFile?')"
  [ "$json_test" = "true" ]
  return
}
function get_videofile_info {
  # Get video file information

  call_api 0 "Getting video file information for $striptracks_videofile_api '$striptracks_videofile_id'." "GET" "$striptracks_videofile_api/$striptracks_videofile_id"
  local json_test="$(echo $striptracks_result | jq -crM '.path?')"
  [ "$json_test" != "null" ] && [ "$json_test" != "" ]
  return
}
function get_profiles {
  # Get profiles

  local profile_type="$1" # 'quality' or 'language'

  call_api 1 "Getting list of $profile_type profiles." "GET" "${profile_type}profile"
  local json_test="$(echo $striptracks_result | jq -crM '.message?')"
  [ "$json_test" != "NotFound" ]
  return
}
function get_language_codes {
  # Get language codes

  local endpoint="language"
  if check_compat languageprofile; then
    local endpoint="languageprofile"
  fi
  call_api 1 "Getting list of language codes." "GET" "$endpoint"
  local json_test="$(echo $striptracks_result | jq -crM '.[] | .name')"
  [ "$json_test" != "null" ] && [ "$json_test" != "" ]
  return
}
function get_custom_formats {
  # Get custom formats

  call_api 1 "Getting list of custom formats." "GET" "customformat"
  local json_test="$(echo $striptracks_result | jq -crM '.[] | .name')"
  [ "$json_test" != "null" ] && [ "$json_test" != "" ]
  return
}
function get_media_config {
  # Get media management configuration

  call_api 0 "Getting ${striptracks_type^} configuration." "GET" "config/mediamanagement"
  local json_test="$(echo $striptracks_result | jq -crM '.id?')"
  [ "$json_test" != "null" ] && [ "$json_test" != "" ]
  return
}
function cache_media_libraries {
  # Cache full movie/series lists to temp files for path matching

  if [ -n "$striptracks_radarr_api_url" ]; then
    [ $striptracks_debug -ge 1 ] && echo "Debug|Caching Radarr movie library" | log
    set_api_context radarr
    call_api 1 "Getting movie list." "GET" "movie"
    if [ $? -eq 0 ] && [ -n "$striptracks_result" ]; then
      export striptracks_radarr_cache=$(mktemp)
      echo "$striptracks_result" > "$striptracks_radarr_cache"
      local count=$(jq 'length' "$striptracks_radarr_cache")
      echo "Info|Cached $count movies from Radarr" | log
      unset striptracks_result
    else
      echo "Warn|Failed to cache Radarr movie library" | log
    fi
  fi

  if [ -n "$striptracks_sonarr_api_url" ]; then
    [ $striptracks_debug -ge 1 ] && echo "Debug|Caching Sonarr series library" | log
    set_api_context sonarr
    call_api 1 "Getting series list." "GET" "series"
    if [ $? -eq 0 ] && [ -n "$striptracks_result" ]; then
      export striptracks_sonarr_cache=$(mktemp)
      echo "$striptracks_result" > "$striptracks_sonarr_cache"
      local count=$(jq 'length' "$striptracks_sonarr_cache")
      echo "Info|Cached $count series from Sonarr" | log
      unset striptracks_result
    else
      echo "Warn|Failed to cache Sonarr series library" | log
    fi
  fi
}
function match_file_to_media {
  # Match a video file path to a Radarr movie or Sonarr series

  local filepath="$1"
  export striptracks_matched=false

  # Try Radarr
  if [ -n "$striptracks_radarr_cache" ]; then
    local match=$(jq -crM --arg path "$filepath" '
      .[] | select(.movieFile.path == $path or (.path as $mpath | $path | startswith($mpath))) |
      {id, movieFileId: .movieFile.id, qualityProfileId, title, year, originalLanguage: .originalLanguage.name}
    ' "$striptracks_radarr_cache" | head -1)

    if [ -n "$match" ] && [ "$match" != "null" ]; then
      set_api_context radarr
      export striptracks_video_api="movie"
      export striptracks_video_id="$(echo $match | jq -crM .id)"
      export striptracks_videofile_api="moviefile"
      export striptracks_videofile_id="$(echo $match | jq -crM .movieFileId)"
      export striptracks_rescan_id="$striptracks_video_id"
      export striptracks_json_quality_root="movieFile"
      export striptracks_video_type="movie"
      export striptracks_video_rootNode=""
      export striptracks_rescan_api="RescanMovie"
      [ $striptracks_debug -ge 1 ] && echo "Debug|Matched to Radarr: $(echo $match | jq -crM '.title') ($(echo $match | jq -crM '.year')) ID:$striptracks_video_id" | log

      local origLang="$(echo $match | jq -crM '.originalLanguage')"
      if [ -n "$origLang" ] && [ "$origLang" != "null" ] && [ -z "$striptracks_originalLangCode" ]; then
        export striptracks_originalLangCode="$(resolve_lang_to_iso "$origLang")"
        [ $striptracks_debug -ge 1 ] && echo "Debug|Original language from Radarr: $origLang ($striptracks_originalLangCode)" | log
      fi
      export striptracks_matched=true
      return 0
    fi
  fi

  # Try Sonarr
  if [ -n "$striptracks_sonarr_cache" ]; then
    local match=$(jq -crM --arg path "$filepath" '
      .[] | select(.path as $spath | $path | startswith($spath)) |
      {id, qualityProfileId, title, originalLanguage: .originalLanguage.name}
    ' "$striptracks_sonarr_cache" | head -1)

    if [ -n "$match" ] && [ "$match" != "null" ]; then
      set_api_context sonarr
      local series_id="$(echo $match | jq -crM .id)"
      export striptracks_video_api="episode"
      export striptracks_videofile_api="episodefile"
      export striptracks_rescan_id="$series_id"
      export striptracks_json_quality_root="episodeFile"
      export striptracks_video_type="series"
      export striptracks_video_rootNode=".series"
      export striptracks_rescan_api="RescanSeries"

      # Cache episodefile list per series to avoid repeated API calls
      local epfile_cache="/tmp/striptracks_epfiles_${series_id}.json"
      if [ ! -f "$epfile_cache" ]; then
        call_api 1 "Getting episode files for series $series_id." "GET" "episodefile" "seriesId=$series_id"
        if [ $? -eq 0 ] && [ -n "$striptracks_result" ]; then
          echo "$striptracks_result" > "$epfile_cache"
        fi
      else
        [ $striptracks_debug -ge 1 ] && echo "Debug|Using cached episodefile list for series $series_id" | log
      fi

      if [ -f "$epfile_cache" ]; then
        local epfile=$(jq -crM --arg path "$filepath" '.[] | select(.path == $path) | {id, episodeId: .episodes[0].id}' "$epfile_cache" | head -1)
        if [ -n "$epfile" ] && [ "$epfile" != "null" ]; then
          export striptracks_videofile_id="$(echo $epfile | jq -crM .id)"
          export striptracks_video_id="$(echo $epfile | jq -crM .episodeId)"
        else
          export striptracks_videofile_id=""
          export striptracks_video_id=""
        fi
      else
        export striptracks_videofile_id=""
        export striptracks_video_id=""
      fi
      [ $striptracks_debug -ge 1 ] && echo "Debug|Matched to Sonarr: $(echo $match | jq -crM '.title') SeriesID:$series_id EpisodeFileID:${striptracks_videofile_id:-none}" | log

      local origLang="$(echo $match | jq -crM '.originalLanguage')"
      if [ -n "$origLang" ] && [ "$origLang" != "null" ] && [ -z "$striptracks_originalLangCode" ]; then
        export striptracks_originalLangCode="$(resolve_lang_to_iso "$origLang")"
        [ $striptracks_debug -ge 1 ] && echo "Debug|Original language from Sonarr: $origLang ($striptracks_originalLangCode)" | log
      fi
      export striptracks_matched=true
      return 0
    fi
  fi

  [ $striptracks_debug -ge 1 ] && echo "Debug|No Radarr/Sonarr match for: $filepath" | log
  return 1
}
