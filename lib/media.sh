#!/bin/bash
# striptracks - Media
# Media info extraction, compatibility checks, video validation, and language detection.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function get_mediainfo {
  # Read in the output of mkvmerge info extraction (see issue #87)

  local videofile="$1"  # Video file to inspect

  local mkvcommand="/usr/bin/mkvmerge"
  execute_mkv_command "inspecting video" "$mkvcommand" -J "$videofile"
  local return=$?

  unset striptracks_json
  # This must be a declare statement to avoid the 'Argument list too long' error with some large returned JSON (see issue #104)
  declare -g striptracks_json
  striptracks_json="$striptracks_mkvresult"
  return $return
}
function check_compat {
  # Compatibility checker

  # Exit codes:
  #  0 - the feature is compatible
  #  1 - the feature is incompatible

  local compat_type="$1" # 'apiv3', 'languageprofile', 'customformat', 'originallanguage', 'qualitylanguage'

  local return=1
  case "$compat_type" in
    apiv3)
      [ ${striptracks_arr_version/.*/} -ge 3 ] && local return=0
    ;;
    languageprofile)
      # Language Profiles
      [ "${striptracks_type,,}" = "sonarr" ] && [ ${striptracks_arr_version/.*/} -eq 3 ] && local return=0
    ;;
    customformat)
      # Language option in Custom Formats
      [ "${striptracks_type,,}" = "radarr" ] && [ ${striptracks_arr_version/.*/} -ge 3 ] && local return=0
      [ "${striptracks_type,,}" = "sonarr" ] && [ ${striptracks_arr_version/.*/} -ge 4 ] && local return=0
    ;;
    originallanguage)
      # Original language selection
      [ "${striptracks_type,,}" = "radarr" ] && [ ${striptracks_arr_version/.*/} -ge 3 ] && local return=0
      [ "${striptracks_type,,}" = "sonarr" ] && [ ${striptracks_arr_version/.*/} -ge 4 ] && local return=0
    ;;
    qualitylanguage)
      # Language option in Quality Profile
      [ "${striptracks_type,,}" = "radarr" ] && [ ${striptracks_arr_version/.*/} -ge 3 ] && local return=0
    ;;
    *)
      # Unknown feature
      local message="Error|Unknown feature $compat_type in ${striptracks_type^}"
      echo "$message" | log
      echo_ansi "$message" >&2
    ;;
  esac
  [ $striptracks_debug -ge 1 ] && echo "Debug|Feature $compat_type is $([ $return -eq 1 ] && echo "not ")compatible with ${striptracks_type^} v${striptracks_arr_version}" | log
  return $return
}
function check_video {
  # Video file checks

  # Check if video file variable is blank
  if [ -z "$striptracks_video" ]; then
    local message="Error|No video file specified. Use -f or -D option."
    echo "$message" | log
    echo_ansi "$message" >&2
    usage
    end_script 1
  fi

  # Check if source video exists
  if [ ! -f "$striptracks_video" ]; then
    local message="Error|Input video file not found: '$striptracks_video'"
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 5
  fi

  # Test for hardlinked file (see issue #85)
  local refcount=$(stat -c %h "$striptracks_video")
  [ $striptracks_debug -ge 1 ] && echo "Debug|Input file has a hard link count of $refcount" | log
  if [ "$refcount" != "1" ]; then
    local message="Warn|Input video file is a hardlink and this will be broken by remuxing."
    echo "$message" | log
    echo_ansi "$message" >&2
  fi

  # Create temporary filename
  local basename="$(basename -- "${striptracks_newvideo}")"
  local fileroot="${basename%.*}"
  # ._ prefixed files are ignored by Radarr/Sonarr (see issues #65 and #115)
  export striptracks_tempvideo="$(dirname -- "${striptracks_newvideo}")/$(mktemp -u -- "._${fileroot:0:5}.tmp.XXXXXX")"
  [ $striptracks_debug -ge 1 ] && echo "Debug|Using temporary file '$striptracks_tempvideo'" | log
}
function detect_languages {
  # Detect languages configured in Radarr/Sonarr, quality of video, etc.

  # Bypass if no API is configured
  if [ -z "$striptracks_api_url" ]; then
    [ $striptracks_debug -ge 1 ] && echo "Debug|No API configured, skipping language auto-detection." | log
    return
  fi

  # Get list of all language IDs
  if ! get_language_codes; then
    # Get language codes API failed
    local message="Warn|Unable to retrieve language codes from 'language' API (curl error or returned a null name)."
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 17
    return
  fi
  export striptracks_lang_codes="$striptracks_result"

  # Get video profile
  if ! get_video_info; then
    # 'hasFile' is not True in returned JSON.
    local message="Warn|Could not find a video file for $striptracks_video_api id '$striptracks_video_id'"
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 17
  fi
  export striptracks_videoinfo="$striptracks_result"
  export striptracks_videomonitored="$(echo "$striptracks_videoinfo" | jq -crM ".monitored")"
  # This is not strictly necessary as the ID is normally set in the environment. However, this is needed for testing scripts and it doesn't hurt to use the data returned by the API call.
  export striptracks_videofile_id="$(echo $striptracks_videoinfo | jq -crM .${striptracks_json_quality_root}.id)"

  # Get video file info
  if ! get_videofile_info; then
    local message="Warn|The '$striptracks_videofile_api' API with id $striptracks_videofile_id returned no path."
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 20
  fi
  export striptracks_videofile_info="$striptracks_result"

  # Get quality profile info
  if ! get_profiles quality; then
    # Get qualityprofile API failed
    local message="Warn|Unable to retrieve quality profiles from ${striptracks_type^} API"
    echo "$message" | log
    echo_ansi "$message" >&2
    change_exit_status 17
  fi
  local qualityProfiles="$striptracks_result"

  # Get language name(s) from quality profile used by video
  local profileId="$(echo $striptracks_videoinfo | jq -crM ${striptracks_video_rootNode}.qualityProfileId)"
  local profileName="$(echo $qualityProfiles | jq -crM ".[] | select(.id == $profileId).name")"
  local profileLanguages="$(echo $qualityProfiles | jq -cM "[.[] | select(.id == $profileId) | .language]")"
  local languageSource="quality profile"
  check_compat qualitylanguage && local qualityLanguage=" with language '$(echo $profileLanguages | jq -crM '[.[] | "\(.name) (\(.id | tostring))"] | join(",")')'"
  [ $striptracks_debug -ge 1 ] && echo "Debug|Found quality profile '${profileName} (${profileId})'$qualityLanguage" | log

  # Query custom formats if returned language from quality profile is null or -1 (Any)
  if [ -z "$profileLanguages" -o "$profileLanguages" = "[null]" -o "$(echo $profileLanguages | jq -crM '.[].id')" = "-1" ] && check_compat customformat; then
    [ $striptracks_debug -ge 1 ] && [ "$(echo $profileLanguages | jq -crM '.[].id')" = "-1" ] && echo "Debug|Language selection of 'Any' in quality profile. Deferring to Custom Format language selection if it exists." | log
    # Get list of Custom Formats, and hopefully languages
    get_custom_formats
    local customFormats="$striptracks_result"
    [ $striptracks_debug -ge 1 ] && echo "Debug|Processing custom format(s) '$(echo "$customFormats" | jq -crM '[.[] | select(.specifications[].implementation == "LanguageSpecification") | .name] | unique | join(",")')'" | log

    # Pick our languages by combining data from quality profile and custom format configuration.
    # I'm open to suggestions if there's a better way to get this list or selected languages.
    # Did I mention that JQ is crazy hard?
    local qcf_langcodes=$(echo "$qualityProfiles $customFormats" | jq -s -crM --argjson ProfileId $profileId '
      [
        # This combines the custom formats [1] with the quality profiles [0], iterating over custom formats that
        # specify languages and evaluating the scoring from the selected quality profile.
        (
          .[1] | .[] |
          {id, specs: [.specifications[] | select(.implementation == "LanguageSpecification") | {langCode: .fields[] | select(.name == "value").value, negate, except: ((.fields[] | select(.name == "exceptLanguage").value) // false)}]}
        ) as $CustomFormat |
        .[0] | .[] |
        select(.id == $ProfileId) | .formatItems[] | select(.format == $CustomFormat.id) |
        {format, name, score, specs: $CustomFormat.specs}
      ] |
      [
        # Only count languages with positive scores plus languages with negative scores that are negated, and
        # languages with negative scores that use Except
        .[] |
        (select(.score > 0) | .specs[] | select(.negate == false and .except == false)),
        (select(.score < 0) | .specs[] | select(.negate == true and .except == false)),
        (select(.score < 0) | .specs[] | select(.negate == false and .except == true)) |
        .langCode
      ] |
      unique | join(",")
    ')
    [ $striptracks_debug -ge 2 ] && echo "Debug|Custom format language code(s) '$qcf_langcodes' were selected based on quality profile scores." | log

    if [ -n "$qcf_langcodes" ]; then
      # Convert the language codes into language code/name pairs
      local profileLanguages="$(echo $striptracks_lang_codes | jq -crM "map(select(.id | inside($qcf_langcodes)) | {id, name})")"
      local languageSource="custom format"
      [ $striptracks_debug -ge 1 ] && echo "Debug|Found custom format language(s) '$(echo $profileLanguages | jq -crM '[.[] | "\(.name) (\(.id | tostring))"] | join(",")')'" | log
    else
      [ $striptracks_debug -ge 1 ] && echo "Debug|None of the applied custom formats have language conditions with usable scores." | log
    fi
  fi

  # Check if the languageprofile API is supported (only in legacy Sonarr; but it was *way* better than Custom Formats <sigh>)
  if [ -z "$profileLanguages" -o "$profileLanguages" = "[null]" ] && check_compat languageprofile; then
    [ $striptracks_debug -ge 1 ] && echo "Debug|No language found in quality profile or in custom formats. This is normal in legacy versions of Sonarr." | log
    if get_profiles language; then
      local languageProfiles="$striptracks_result"

      # Get language name(s) from language profile used by video
      local profileId="$(echo $striptracks_videoinfo | jq -crM .series.languageProfileId)"
      local profileName="$(echo $languageProfiles | jq -crM ".[] | select(.id == $profileId).name")"
      local profileLanguages="$(echo $languageProfiles | jq -cM "[.[] | select(.id == $profileId) | .languages[] | select(.allowed).language]")"
      local languageSource="language profile"
      [ $striptracks_debug -ge 1 ] && echo "Debug|Found language profile '(${profileId}) ${profileName}' with language(s) '$(echo $profileLanguages | jq -crM '[.[].name] | join(",")')'" | log
    else
      # languageProfile API failed
      local message="Warn|The 'languageprofile' API returned an error."
      echo "$message" | log
      echo_ansi "$message" >&2
      change_exit_status 17
    fi
  fi

  # Check if after all of the above we still couldn't get any languages
  if [ -z "$profileLanguages" -o "$profileLanguages" = "[null]" ]; then
    local message="Warn|No languages found in any profile or custom format. Unable to use automatic language detection."
    echo "$message" | log
    echo_ansi "$message" >&2
  else
    # Final determination of configured languages in profiles or custom formats
    local profileLangNames="$(echo $profileLanguages | jq -crM '[.[].name]')"
    [ $striptracks_debug -ge 1 ] && echo "Debug|Determined ${striptracks_type^} configured language(s) of '$(echo $profileLanguages | jq -crM '[.[] | "\(.name) (\(.id | tostring))"] | join(",")')' from $languageSource" | log
  fi

  # Get originalLanguage of video
  if check_compat originallanguage; then
    local originalLangName="$(echo $striptracks_videoinfo | jq -crM ${striptracks_video_rootNode}.originalLanguage.name)"

    # shellcheck disable=SC2090
    export striptracks_originalLangCode="$(resolve_lang_to_iso "$originalLangName")"
    [ $striptracks_debug -ge 1 ] && echo "Debug|Found original video language of '$originalLangName (${striptracks_originalLangCode#:})' from $striptracks_video_type '$striptracks_rescan_id'" | log
  fi

  # Map language names to ISO code(s) used by mkvmerge
  unset striptracks_profileLangCodes
  for templang in $(echo $profileLangNames | jq -crM '.[]'); do
    # Convert 'Original' language selection to specific video language
    if [ "$templang" = "Original" ]; then
      local templang="$originalLangName"
    fi
    # shellcheck disable=SC2090
    export striptracks_profileLangCodes+="$(resolve_lang_to_iso "$templang")"
  done
  [ $striptracks_debug -ge 1 ] && echo "Debug|Mapped $languageSource language(s) '$(echo $profileLangNames | jq -crM "join(\",\")")' to ISO639-2 code list '$striptracks_profileLangCodes'" | log
}
