#!/bin/bash
# striptracks - Tracks
# MKV track processing, reordering, default track mapping, and early-exit logic.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function process_mkvmerge_json {
  # Process JSON data from MKVmerge; track selection logic
  # Use unified shell parser and convert into the rules structure jq expects
  local audio_rules_json
  local subs_rules_json
  audio_rules_json=$(parse_language_codes_to_json "$striptracks_audiokeep" "audio")
  subs_rules_json=$(parse_language_codes_to_json "$striptracks_subskeep" "subtitles")

  export striptracks_json_processed=$(echo "$striptracks_json" | jq -jcM --argjson AudioRulesJSON "$audio_rules_json" \
    --argjson SubsRulesJSON "$subs_rules_json" '
    # Convert JSON rules array (from parse_language_codes_to_json) into rules objects
    # Build rules object with languages, forced_languages and default_languages legacy maps
    # Yes, this is cheating, but it saves me from completely rewriting the logic today. The rules objects have three maps: languages, forced_languages, and default_languages.
    def parse_to_rules(arr):
      (arr | map({lang, limit, mods})) as $lang_code |
      { languages: ($lang_code | map(select(.mods == []) | {(.lang): .limit}) | add // {}),
        forced_languages: ($lang_code | map(select(.mods[]? | .forced) | {(.lang): (.limit // -1)}) | add // {}),
        default_languages: ($lang_code | map(select(.mods[]? | .default) | {(.lang): (.limit // -1)}) | add // {}),
        not_forced_languages: ($lang_code | map(select(.mods[]? | .forced == false) | {(.lang): (.limit // -1)}) | add // {}),
        not_default_languages: ($lang_code | map(select(.mods[]? | .default == false) | {(.lang): (.limit // -1)}) | add // {})
      };

    parse_to_rules($AudioRulesJSON) as $AudioRules |
    parse_to_rules($SubsRulesJSON) as $SubsRules |

    # Log chapter information
    if (.chapters[0].num_entries) then
      .striptracks_log = "Info|Chapters: \(.chapters[].num_entries)"
    else . end |

    # Process tracks
    reduce .tracks[] as $track (
      # Create object to hold tracks and counters for each reduce iteration
      # This is what will be output at the end of the reduce loop
      {"tracks": [], "counters": {"audio": {"normal": {}, "forced": {}, "default": {}, "not_forced": {}, "not_default": {}}, "subtitles": {"normal": {}, "forced": {}, "default": {}, "not_forced": {}, "not_default": {}}}};

      # Set track language to "und" if null or empty
      # NOTE: The // operator cannot be used here because it checks for null or empty values, not blank strings
      (if ($track.properties.language == "" or $track.properties.language == null) then "und" else $track.properties.language end) as $track_lang |

      # Initialize counters for each track type and language
      (.counters[$track.type].normal[$track_lang] //= 0) |
      if $track.properties.forced_track then (.counters[$track.type].forced[$track_lang] //= 0) else . end |
      if $track.properties.default_track then (.counters[$track.type].default[$track_lang] //= 0) else . end |
      if $track.properties.forced_track != true then (.counters[$track.type].not_forced[$track_lang] //= 0) else . end |
      if $track.properties.default_track != true then (.counters[$track.type].not_default[$track_lang] //= 0) else . end |
      .counters[$track.type] as $track_counters |

      # Add tracks one at a time to output object above
      .tracks += [
        $track |
        .striptracks_debug_log = "Debug|Parsing track ID:\(.id) Type:\(.type) Name:\(.properties.track_name) Lang:\($track_lang) Codec:\(.codec) Default:\(.properties.default_track) Forced:\(.properties.forced_track)" |
        # Use track language evaluation above
        .properties.language = $track_lang |

        # Determine keep logic based on type and rules
        if .type == "video" then
          .striptracks_keep = true
        elif .type == "audio" or .type == "subtitles" then
          .striptracks_log = "\(.id): \($track_lang) (\(.codec))\(if .properties.track_name then " \"" + .properties.track_name + "\"" else "" end)" |
          # Same logic for both audio and subtitles
          (if .type == "audio" then $AudioRules else $SubsRules end) as $currentRules |
          if ($currentRules.languages["any"] == -1 or ($track_counters.normal | add) < $currentRules.languages["any"] or
              $currentRules.languages[$track_lang] == -1 or $track_counters.normal[$track_lang] < $currentRules.languages[$track_lang]) then
            .striptracks_keep = true
          elif (.properties.forced_track and
                ($currentRules.forced_languages["any"] == -1 or ($track_counters.forced | add) < $currentRules.forced_languages["any"] or
                  $currentRules.forced_languages[$track_lang] == -1 or $track_counters.forced[$track_lang] < $currentRules.forced_languages[$track_lang])) then
            .striptracks_keep = true |
            .striptracks_rule = "forced"
          elif (.properties.forced_track != true and
                ($currentRules.not_forced_languages["any"] == -1 or ($track_counters.not_forced | add) < $currentRules.not_forced_languages["any"] or
                  $currentRules.not_forced_languages[$track_lang] == -1 or $track_counters.not_forced[$track_lang] < $currentRules.not_forced_languages[$track_lang])) then
            .striptracks_keep = true |
            .striptracks_rule = "not_forced"
          elif (.properties.default_track and
                ($currentRules.default_languages["any"] == -1 or ($track_counters.default | add) < $currentRules.default_languages["any"] or
                  $currentRules.default_languages[$track_lang] == -1 or $track_counters.default[$track_lang] < $currentRules.default_languages[$track_lang])) then
            .striptracks_keep = true |
            .striptracks_rule = "default"
          elif (.properties.default_track != true and
                ($currentRules.not_default_languages["any"] == -1 or ($track_counters.not_default | add) < $currentRules.not_default_languages["any"] or
                  $currentRules.not_default_languages[$track_lang] == -1 or $track_counters.not_default[$track_lang] < $currentRules.not_default_languages[$track_lang])) then
            .striptracks_keep = true |
            .striptracks_rule = "not_default"
          else . end |
          if .striptracks_keep then
            .striptracks_log = "Info|Keeping \(if .striptracks_rule then .striptracks_rule + " " else "" end)\(.type) track " + .striptracks_log
          else
            .striptracks_keep = false
          end
        else . end
      ] |

      # Increment counters for each track type and language
      .counters[$track.type].normal[$track_lang] +=
        if .tracks[-1].striptracks_keep then
          1
        else 0 end |
      .counters[$track.type].forced[$track_lang] +=
        if ($track.properties.forced_track and .tracks[-1].striptracks_keep) then
          1
        else 0 end |
      .counters[$track.type].default[$track_lang] +=
        if ($track.properties.default_track and .tracks[-1].striptracks_keep) then
          1
        else 0 end |
      .counters[$track.type].not_forced[$track_lang] +=
        if ($track.properties.forced_track != true and .tracks[-1].striptracks_keep) then
          1
        else 0 end |
      .counters[$track.type].not_default[$track_lang] +=
        if ($track.properties.default_track != true and .tracks[-1].striptracks_keep) then
          1
        else 0 end
    ) |

    # Ensure at least one audio track is kept
    if ((.tracks | map(select(.type == "audio")) | length == 1) and (.tracks | map(select(.type == "audio" and .striptracks_keep)) | length == 0)) then
      # If there is only one audio track and none are kept, keep the only audio track
      .tracks |= map(if .type == "audio" then
          .striptracks_log = "Warn|No audio tracks matched! Keeping only audio track " + .striptracks_log |
          .striptracks_keep = true
        else . end)
    elif (.tracks | map(select(.type == "audio" and .striptracks_keep)) | length == 0) then
      # If no audio tracks are kept, first try to keep the default audio track
      .tracks |= map(if .type == "audio" and .properties.default_track then
          .striptracks_log = "Warn|No audio tracks matched! Keeping default audio track " + .striptracks_log |
          .striptracks_keep = true
        else . end) |
      # If still no audio tracks are kept, keep the first audio track
      if (.tracks | map(select(.type == "audio" and .striptracks_keep)) | length == 0) then
        (first(.tracks[] | select(.type == "audio"))) |= . +
        {striptracks_log: ("Warn|No audio tracks matched! Keeping first audio track " + .striptracks_log),
        striptracks_keep: true}
      else . end
    else . end |

    # Output simplified dataset
    { striptracks_log, tracks: .tracks | map({ id, type, language: .properties.language, name: .properties.track_name, forced: .properties.forced_track, default: .properties.default_track, striptracks_debug_log, striptracks_log, striptracks_keep }) }
  ')
  [ $striptracks_debug -ge 1 ] && echo "Debug|Track processing returned ${#striptracks_json_processed} bytes." | log
  [ $striptracks_debug -ge 2 ] && echo "Track processing returned: $(echo "$striptracks_json_processed" | jq)" | awk '{print "Debug|"$0}' | log

  # Write messages to log
  echo "$striptracks_json_processed" | jq -crM --argjson Debug $striptracks_debug '
    # Join log messages into one line function
    def log_removed_tracks($type):
      if (.tracks | map(select(.type == $type and .striptracks_keep == false)) | length > 0) then
        "Info|Removing \($type) tracks: " +
        (.tracks | map(select(.type == $type and .striptracks_keep == false) | .striptracks_log) | join(", "))
      else empty end;

    # Log the chapters, if any
    .striptracks_log // empty,

    # Log debug messages
    ( .tracks[] | (if $Debug >= 1 then .striptracks_debug_log else empty end),

    # Log messages for kept tracks
    (select(.striptracks_keep) | .striptracks_log // empty)
    ),

    # Log removed tracks
    log_removed_tracks("audio"),
    log_removed_tracks("subtitles"),

    # Summary of kept tracks
    "Info|Kept tracks: \(.tracks | map(select(.striptracks_keep)) | length) " +
    "(audio: \(.tracks | map(select(.type == "audio" and .striptracks_keep)) | length), " +
    "subtitles: \(.tracks | map(select(.type == "subtitles" and .striptracks_keep)) | length))"
  ' | log

  # Check for no audio tracks
  if [ "$(echo "$striptracks_json_processed" | jq -crM '.tracks|map(select(.type=="audio" and .striptracks_keep))')" = "[]" ]; then
    local message="Error|Unable to determine any audio tracks to keep. Exiting."
    echo "$message" | log
    echo_ansi "$message" >&2
    end_script 11
  fi
}
function determine_track_order {
  # Determine current and new track order for mkvmerge
  # Example text output: 0:0,0:2,0:5,0:4,0:27

  # Map current track order
  export striptracks_order=$(echo "$striptracks_json_processed" | jq -jcM '.tracks | map(select(.striptracks_keep) | .id | "0:" + tostring) | join(",")')
  [ $striptracks_debug -ge 1 ] && echo "Debug|Current mkvmerge track order: $striptracks_order" | log

  # Prepare to reorder tracks if option is enabled (see issue #92)
  if [ "$striptracks_reorder" = "true" ]; then
    # Use parsed language rules from shell parser
    local audio_rules_json
    local subs_rules_json
    audio_rules_json=$(parse_language_codes_to_json "$striptracks_audiokeep" "audio")
    subs_rules_json=$(parse_language_codes_to_json "$striptracks_subskeep" "subtitles")

    export striptracks_neworder=$(echo "$striptracks_json_processed" | jq -jcM --argjson AudioRulesJSON "$audio_rules_json" \
      --argjson SubsRulesJSON "$subs_rules_json" '
      # Reorder tracks function using parsed rules arrays
      # Same cheating here as in process_mkvmerge_json function
      def parsed_rules_list(arr): arr | map({lang, mods});

      def order_tracks(tracks; rulesArr; tracktype):
        parsed_rules_list(rulesArr) as $rules |
        reduce $rules[] as $rule (
          [];
          . as $orderedTracks |
          . += [tracks |
          map(. as $track |
            select(.type == tracktype and .striptracks_keep and
              ($rule.lang | in({"any":0,($track.language):0})) and
              (
                ($rule.mods | length == 0) or
                ( ($rule.mods | map(.forced? // false) | index(true) != null) and $track.forced ) or
                ( ($rule.mods | map(.default? // false) | index(true) != null) and $track.default )
              )
            ) |
            .id as $id |
            if ([$id] | flatten | inside($orderedTracks | flatten)) then empty else $id end
          )]
        ) | flatten;

      # Reorder audio and subtitles according to language code order
      .tracks as $tracks |
      order_tracks($tracks; $AudioRulesJSON; "audio") as $audioOrder |
      order_tracks($tracks; $SubsRulesJSON; "subtitles") as $subsOrder |

      # Output ordered track string compatible with the mkvmerge --track-order option
      # Video tracks are always first, followed by audio tracks, then subtitles
      # NOTE: If there is only one audio track and it does not match a code in AudioKeep, it will not appear in the new track order string
      # NOTE: Other track types are still preserved as mkvmerge will automatically place any missing tracks after those listed per https://mkvtoolnix.download/doc/mkvmerge.html#mkvmerge.description.track_order
      $tracks | map(select(.type == "video") | .id) + $audioOrder + $subsOrder | map("0:" + tostring) | join(",")
    ')
    [ $striptracks_debug -ge 1 ] && echo "Debug|New mkvmerge track order: $striptracks_neworder" | log
    local message="Info|Reordering tracks using language code order."
    echo "$message" | log
  fi
}
function map_default_tracks {
  # Build mkvpropedit parameters to set default flags on audio and subtitle tracks.

  # Two variables needed because mkvmerge and mkvpropedit use different arguments and track numbering (because of course the do)
  export striptracks_mkvmerge_default_args
  export striptracks_mkvpropedit_default_args

  # Process audio and subtitle --set-default track settings
  for tracktype in audio subtitles; do
    local cfgvar="striptracks_default_${tracktype}"
    local currentcfg="${!cfgvar}"

    if [ -z "$currentcfg" ]; then
      [ $striptracks_debug -ge 1 ] && echo "Debug|No default ${tracktype} track setting specified." | log
      continue
    fi

    # Use JSON from language code parser
    local rules_json
    # The track type argument is not needed here since the default track selection logic is the same for audio and subtitles, but we have to pass something
    # or the parser will treat it as audio and add "mis" and "zxx" codes that we don't want for this logic
    rules_json=$(parse_language_codes_to_json "$currentcfg" "dummy")

    # Use jq to find the track ID using case-insensitive substring match on track name, trying each rule until one matches
    local track_id=$(echo "$striptracks_json_processed" | jq -crM --arg type "$tracktype" --argjson RulesJSON "$rules_json" '
      . as $tracks |
      # Loop through rules and find the first track that matches each rule
      $RulesJSON |
      map(. as $rule |
        $tracks | .tracks |
        map(. as $track |
          (($rule.lang == "any" or $rule.lang == $track.language) as $lang_match |
            ($rule.match == "" or (($track.name // "") | ascii_downcase | contains(($rule.match // "") | ascii_downcase))) as $name_match |
            ($rule.mods as $mods | ($mods | map(select(.forced != null) | .forced) | first) as $forced_mod |
              ($mods | map(select(.default != null) | .default) | first) as $default_mod |
              ((if $forced_mod == true then $track.forced == true elif $forced_mod == false then $track.forced != true else true end)
                and
                (if $default_mod == true then $track.default == true elif $default_mod == false then $track.default != true else true end)
              )
            ) as $mod_match |
            select($track.type == $type and $lang_match and $name_match and $mod_match and .striptracks_keep)
          )
        ) |
        .[0].id |
        # Exclude null matches
        select(length > 0)
      ) |
      # Select the first matching track ID
      .[0] // ""
    ')

    # No track matched
    if [ -z "$track_id" ]; then
      local message="Warn|No ${tracktype} track matched default specification '${currentcfg}'. No changes made to default ${tracktype} tracks."
      echo "$message" | log
      continue
    fi

    # Use variables to hold full argument string (unset others of same type)
    # The track IDs must be converted to 1-based for mkvpropedit (add 1)
    striptracks_mkvmerge_default_args+=" --default-track-flag ${track_id}:1"
    striptracks_mkvpropedit_default_args+=" --edit track:$((track_id + 1)) --set flag-default=1"
    # Find other kept tracks of same type to unset default flag
    local unset_ids=$(echo "$striptracks_json_processed" | jq -crM --arg type "$tracktype" --argjson track_id "$track_id" '.tracks | map(select(.type == $type and .striptracks_keep and .id != $track_id) | .id) | join(",")')
    striptracks_mkvmerge_default_args+="$(echo $unset_ids | awk 'BEGIN {RS=","}; /[0-9]+/ {print " --default-track-flag " $0 ":0"}' | tr -d '\n')"
    striptracks_mkvpropedit_default_args+="$(echo $unset_ids | awk 'BEGIN {RS=","}; /[0-9]+/ {print " --edit track:" ($0 += 1) " --set flag-default=0"}' | tr -d '\n')"
    local message="Info|Setting ${tracktype} track ${track_id} as default$([ -n "$unset_ids" ] && echo " and removing default from track(s) '$unset_ids'")."
    echo "$message" | log
    # Remove leading space
    striptracks_mkvmerge_default_args="${striptracks_mkvmerge_default_args# }"
    striptracks_mkvpropedit_default_args="${striptracks_mkvpropedit_default_args# }"
  done
}
function set_title_and_exit_if_nothing_removed {
  # If no tracks are removed, and a variety of other conditions are met, we can skip remuxing, set the title, and exit early

  # Return if any audio or subtitle tracks would be removed
  if [ "$(echo "$striptracks_json" | jq -crM '.tracks|map(select(.type=="audio" or .type=="subtitles"))|length')" != "$(echo "$striptracks_json_processed" | jq -crM '.tracks|map(select((.type=="audio" or .type=="subtitles") and .striptracks_keep))|length')" ]; then
    return
  fi

  # All tracks matched/no tracks removed (see issues #49 and #89)
  [ $striptracks_debug -ge 1 ] && echo "Debug|No tracks will be removed from video '$striptracks_video'" | log

  # Check if already MKV
  if ! [[ $striptracks_video == *.mkv ]]; then
    # Not MKV
    [ $striptracks_debug -ge 1 ] && echo "Debug|Source video is not MKV. Remuxing anyway." | log
    return
  fi

  # Check if reorder option is set or if the order would change (see issue #92)
  if [ "$striptracks_reorder" = "true" -a "$striptracks_order" != "$striptracks_neworder" ]; then
    # Reorder tracks anyway
    local message="Info|No tracks will be removed from video, but they can be reordered. Remuxing anyway."
    echo "$message" | log
    return
  fi

  # Remuxing not performed
  local message="Info|No tracks would be removed from video$( [ "$striptracks_reorder" = "true" ] && echo " or reordered"). Setting Title only and exiting."
  echo "$message" | log
  local mkvcommand="/usr/bin/mkvpropedit"
  execute_mkv_command "setting video title" "$mkvcommand" -q --edit info --set "title=$(escape_string "$striptracks_title")" $striptracks_mkvpropedit_default_args "$striptracks_newvideo"
  end_script
}
