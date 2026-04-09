#!/bin/bash
# striptracks - Language
# Language code resolution, :org code handling, and language code parsing.
#
# Sourced by striptracks-standalone.sh. Do not execute directly.

function resolve_lang_to_iso {
  # Resolve a language name to ISO639-2 codes prefixed with colons

  local lang_name="$1"
  echo "$striptracks_isocodemap" | jq -jcM ".languages[] | select(.language.name == \"$lang_name\") | .language | \":\(.\"iso639-2\"[])\""
}
function process_org_code {
  # Handle :org language code

  local track_type="$1" # 'audio' or 'subtitles'
  local keep_var="$2"  # variable name containing language codes

  if [[ "${!keep_var}" =~ :org ]]; then
    if [ -z "$striptracks_originalLangCode" ]; then
      local message="Warn|${track_type^} argument contains ':org' code, but no original language is available. Use --original-language or configure API access."
      echo "$message" | log
      echo_ansi "$message" >&2
      return
    fi

    [ $striptracks_debug -ge 1 ] && echo "Debug|${track_type^} argument ':org' specified. Changing '${!keep_var}' to '${!keep_var//:org/${striptracks_originalLangCode}}'" | log
    declare -g "$keep_var=${!keep_var//:org/${striptracks_originalLangCode}}"
  fi
}
function resolve_code_conflict {
  # Final assignment of audio and subtitles selection

  # Use profile-detected languages as fallback
  if [ -z "$striptracks_audiokeep" ] && [ -n "$striptracks_profileLangCodes" ]; then
    [ $striptracks_debug -ge 1 ] && echo "Debug|No audio languages specified. Using auto-detected codes '$striptracks_profileLangCodes'" | log
    export striptracks_audiokeep="$striptracks_profileLangCodes"
  fi

  if [ -z "$striptracks_audiokeep" ]; then
    local message="Error|No audio languages specified or detected! Use -a or configure API for auto-detection."
    echo "$message" | log
    echo_ansi "$message" >&2
    return 2
  fi

  # Default: strip all embedded subtitles (user uses Bazarr/Plex for external subs)
  if [ -z "$striptracks_subskeep" ]; then
    if [ -n "$striptracks_profileLangCodes" ]; then
      [ $striptracks_debug -ge 1 ] && echo "Debug|No subtitle languages specified. Using auto-detected codes '$striptracks_profileLangCodes'" | log
      export striptracks_subskeep="$striptracks_profileLangCodes"
    else
      local message="Info|No subtitle languages specified. Removing all embedded subtitles."
      echo "$message" | log
      export striptracks_subskeep="null"
    fi
  fi

  [ $striptracks_debug -ge 1 ] && echo "Debug|Using audio languages '$striptracks_audiokeep'" | log
  [ $striptracks_debug -ge 1 ] && echo "Debug|Using subtitle languages '$striptracks_subskeep'" | log
  local message="Info|Keeping audio tracks with codes '$(echo $striptracks_audiokeep | sed -e 's/^://; s/:/,/g')' and subtitle tracks with codes '$(echo $striptracks_subskeep | sed -e 's/^://; s/:/,/g')'"
  echo "$message" | log
}
function parse_language_codes_to_json {
  # Unified parser for language code strings for track selection
  # Input: colon-separated codes, each code: :lang[+|-][modifiers][=match]...
  # Output: JSON array of objects, order matches input
  # Modifiers can be f (forced), d (default), and/or a number (limit of tracks to keep; -1 means all) (see issues #82 and #86)
  # Substring matching when = is used (see issue #86)

  # Example input: :eng+f="Director's Commentary":spa-d
  # Example output: [{"lang":"eng","limit":-1,"mods":[{"forced":true}],"match":"Director's Commentary"},{"lang":"spa","limit":-1,"mods":[],"match":null}]
  # Example input: :eng+1:fre:ger+d:any+f
  # Example output:[{"lang":"eng","limit":1,"mods":[],"match":null},{"lang":"fre","limit":-1,"mods":[],"match":null},{"lang":"ger","limit":-1,"mods":[{"default":true}],"match":null},{"lang":"any","limit":-1,"mods":[{"forced":true}],"match":null}]
  # Example input: # :fre-f:fre+f:eng:und+1=Commentary
  # Example output: [{"lang":"fre","limit":-1,"mods":[{"forced":false}],"match":null},{"lang":"fre","limit":-1,"mods":[{"forced":true}],"match":null},{"lang":"eng","limit":-1,"mods":[],"match":null},{"lang":"und","limit":1,"mods":[],"match":"Commentary"}]

  local input="$1" # Language code string to parse
  local type="${2:-audio}" # Type of code string (audio, subtitles)

  echo "$input" | jq -cRrM --arg trackType "$type" '
    def parse_language_codes_to_json:
      # Remove leading colon
      (if startswith(":") then .[1:] else . end) as $input |

      # Split by colons and filter empty tokens
      (if ($input == "") then [] else ($input | split(":")) end) |

      # Process each token
      map(select(length > 0) |
        . as $token |

        # Extract match specification (everything after =)
        (if test("=") then
          {token: (split("=")[0]), match: (split("=")[1])}
        else
          {token: ., match: null}
        end) as $pm |

        # Extract language code (first 3 chars) and modifiers (rest)
        ($pm.token[0:3]) as $lang |
        ($pm.token[3:]) as $rest |

        # Determine polarity (+ or -) and extract mods string
        (if ($rest | startswith("+")) then
          {polarity: "+", mods_raw: $rest[1:]}
        elif ($rest | startswith("-")) then
          {polarity: "-", mods_raw: $rest[1:]}
        else
          {polarity: "", mods_raw: $rest}
        end) as $pm2 |

        # Extract numeric limit from mods (e.g., "f1d" -> 1)
        (if ($pm2.mods_raw | test("[0-9]+")) then
          ($pm2.mods_raw | [scan("[0-9]+")][0] | tonumber)
        else
          -1
        end) as $limit |

        # Build mods array based on modifiers present
        (
          [] |
          # Add forced modifier if f is present
          if ($pm2.mods_raw | contains("f")) then
            if ($pm2.polarity == "-") then
              . + [{"forced": false}]
            else
              . + [{"forced": true}]
            end
          else
            .
          end |
          # Add default modifier if d is present
          if ($pm2.mods_raw | contains("d")) then
            if ($pm2.polarity == "-") then
              . + [{"default": false}]
            else
              . + [{"default": true}]
            end
          else
            .
          end
        ) as $mods |

        # Build output object
        {lang: $lang, limit: $limit, mods: $mods, match: $pm.match}
      );

    # Entry point
    parse_language_codes_to_json |

    # For audio, preserve all "mis" and "zxx" codes
    if ($trackType == "audio") then
      (if map(.lang) | index("mis") then . else . + [{"lang":"mis","limit":-1,"mods":[],"match":null}] end) |
      (if map(.lang) | index("zxx") then . else . + [{"lang":"zxx","limit":-1,"mods":[],"match":null}] end)
    else
      .
    end
  '
}
