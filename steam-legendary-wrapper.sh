#!/bin/bash

# References:
# - https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/blob/master/docs/steam-compat-tool-interface.md
# - https://gitlab.steamos.cloud/steamrt/steam-runtime-tools/-/merge_requests/134#note_14545
# - https://github.com/ValveSoftware/steam-for-linux/issues/6310

set -m

set_commands(){
  # which
  which="$(which which 2>/dev/null)" || required "wich"
  # coreutils
  basename="$($which basename 2>/dev/null)" || required "basename"
  cat="$($which cat 2>/dev/null)" || required "cat"
  cut="$($which cut 2>/dev/null)" || required "cut"
  dirname="$($which dirname 2>/dev/null)" || required "dirname"
  head="$($which head 2>/dev/null)" || required "head"
  mkdir="$($which mkdir 2>/dev/null)" || required "mkdir"
  printf="$($which printf 2>/dev/null)" || required "printf"
  readlink="$($which readlink 2>/dev/null)" || required "readlink"
  sort="$($which sort 2>/dev/null)" || required "sort"
  tr="$($which tr 2>/dev/null)" || required "tr"
  # findutils
  find="$($which find 2>/dev/null)" || required "find"
  # grep
  grep="$($which grep 2>/dev/null)" || required "grep"
  # glibc
  ldd="$($which ldd 2>/dev/null)" || required "ldd"
  locale="$($which locale 2>/dev/null)" || required "locale"
  # sed
  sed="$($which sed 2>/dev/null)" || required "sed"
  # python 3
  python3_bin="$($which python3 2>/dev/null)" || required "python3"
  #glib2-tools
  gsettings="$($which gsettings 2>/dev/null)"
  #libnotify-tools
  notifysend="$($which notify-send 2>/dev/null)"
  # libqt-qdbus
  qdbus="$($which qdbus-qt5 2>/dev/null || $which qdbus 2>/dev/null)"
  # zenity
  zenity="$($which zenity 2>/dev/null)"
  # https://github.com/toalex77/monitor
  monitor_sh="$($which monitor.sh 2>/dev/null)"
}

command_line_parse(){
  local CMDLINE_PARAMS
  GAME_PARAMS=("$@")
  if [ -n "$1" ] && [ -n "$2" ]; then
    if [ "$1" == "compatrun" ] || [ "$1" == "compatwaitforexitandrun" ]; then
      PROTON_RUN="${1#*compat}"
      GAME_DIR="$($dirname "${2}")"
      shift 2
      GAME_PARAMS=("$@")
      CMDLINE_PARAMS=()
      for p in "${GAME_PARAMS[@]}" ; do
        if [[ $p =~ ^PROTON_VER=.* ]]; then
          PROTON_VER="${p#"PROTON_VER="}"
        elif [[ $p =~ ^STEAM_LINUX_RUNTIME=.* ]]; then
          STEAM_LINUX_RUNTIME="${p#"STEAM_LINUX_RUNTIME="}"
        else
          CMDLINE_PARAMS+=( "$p" )
        fi
      done
      GAME_PARAMS_PRE=()
      GAME_PARAMS=()
      right=0
      if [[ "${CMDLINE_PARAMS[*]}" =~ %command% ]]; then
        for p in "${CMDLINE_PARAMS[@]}"; do
          if [ $right -eq 0 ] && [ "$p" != "%command%" ]; then
            if [[ ! "$p" =~ ^cp|^mv|^rm ]]; then
              GAME_PARAMS_PRE+=( "$p" )
            fi
          elif [ $right -eq 1 ] && [ "$p" != "%command%" ]; then
            GAME_PARAMS+=( "$p" )
          elif [ $right -eq 0 ] && [ "$p" == "%command%" ]; then
            right=1
          fi
        done
      fi
      APP_ID="$(app_name_from_app_dir "${GAME_DIR}")"
      COMPAT_TOOL=1
    fi
  fi

  GAME_PARAMS_COPY=("${GAME_PARAMS[@]}")
  GAME_PARAMS=()
  right=0
  if [ ${#GAME_PARAMS_COPY[@]} -ge 1 ]; then
    cnt=1
    for p in "${GAME_PARAMS_COPY[@]}"; do
      if [ "$p" != "--" ] && [ $right -eq 0 ] && [ $cnt -le 3 ]; then
        if [ -z "${GAME_NAME}" ] && [ $cnt -eq 1 ]; then
          GAME_NAME="$p"
        fi
        if [ -z "${PROTON_VER}" ] && [ $cnt -eq 2 ]; then
          PROTON_VER="$p"
        fi
        if [ -z "${STEAM_LINUX_RUNTIME}" ] && [ $cnt -eq 3 ]; then
          STEAM_LINUX_RUNTIME="$p"
        fi
      else
        right=1
        if [ "$p" != "--" ]; then
          GAME_PARAMS+=( "$p" )
        fi
      fi
      ((cnt++))
    done
  fi
  if [ $COMPAT_TOOL -eq 0 ]; then
    if [ -n "${GAME_NAME}" ]; then
      APP_ID="$(app_id_from_title "${GAME_NAME}")"
      GAME_DIR="$(app_dir_from_title "${GAME_NAME}")"
    fi
  fi
  if [ "${#GAME_PARAMS[@]}" -ne 0 ]; then
    GAME_PARAMS_SEPARATOR="--"
  fi
}

isInSteam() {
  # Return 0 if is in Steam, otherwise 1
  if [ -n "${SteamAppUser}" ] && [ -n "${SteamAppId}" ]; then
    echo -n "0"
    return 0
  fi
  echo -n "1"
  return 1
}

required() {
  showMessage "Command \"$1\" is required." "e"
  exit
}

showMessage() {
  local message="$1"
  local level="${2:-i}"
  local title="Steam Legendary Wrapper"

  declare -A LEVELS
  declare -a LEVEL_ARRAY
  LEVELS[d]="Debug --info --icon=info"
  LEVELS[i]="Info --info --icon=info"
  LEVELS[w]="Warning --warning --icon=dialog-warning"
  LEVELS[e]="Error --error --icon=dialog-error"

  if [ ! ${LEVELS[$level]+_} ]; then
    level="i"
  fi
  LEVEL_ARRAY=( ${LEVELS[$level]} ) 
  if [ "${level}" != "d" ] && [ "$( isInSteam )" -eq 0 ] && [ -n "${zenity}" ]; then
    $zenity "${LEVEL_ARRAY[1]}" --text="$message" --title="${title}" --width=240
  elif [ "${level}" != "d" ] && [ "$( isInSteam )" -eq 0 ] && [ -n "${notifysend}" ]; then
    $notifysend -u normal "${LEVEL_ARRAY[2]}" "$title" "$message"
  else
    echo "${title}"
    echo "${LEVEL_ARRAY[0]}: ${message}"
  fi
}

askQuestion(){
  if [ -n "$1" ]; then
    if [ "$( isInSteam )" -eq 0 ] && [ -n "$zenity" ]; then
      $zenity --question --ellipsize --text "$1"
      return $?
    else
      echo -en "$1 (y/n)? "
      read -r answer
      [ "${answer}" != "${answer#[Yy]}" ]
      return $?
    fi
  else
    return 1
  fi
}

set_language() {
  if [ ! -f "${legendary_config}" ] || [ "$( $grep -c locale "${legendary_config}" 2> /dev/null )" == "0" ]; then
    if [ -n "${LANGUAGE}" ] && [ -n "$($locale -a | $grep "^${LANGUAGE:0:2}")" ]; then
      language="--language ${LANGUAGE:0:2}"
    else
      if [ ! -f "${legendary_config}" ] || [ "$( $grep -c locale "${legendary_config}" 2> /dev/null )" == "0" ]; then
        if [ "${LC_IDENTIFICATION}" != "" ]; then
          language="--language ${LC_IDENTIFICATION:0:2}"
        elif [ "${LANG}" != "" ]; then
          language="--language ${LANG:0:2}"
        elif [ "${LC_ALL}" != "" ]; then
          language="--language ${LC_ALL:0:2}"
        elif [ "${LC_CTYPE}" != "" ]; then
          language="--language ${LC_CTYPE:0:2}"
        fi
      fi
    fi
  fi
}

set_python_vars() {
  if [ ! -f  "${python3_bin}" ]; then
    showMessage "Python 3 executable not found." "e"
    exit
  fi
  PYTHONPATH="$( $python3_bin -c "import sys;print(':'.join(map(str, list(filter(None, sys.path)))))" )"
  PYTHONHOME="$( $dirname "$(echo -n "${python3_bin}")" )"
}

find_legendary_bin(){
  if [ -n "${LEGENDARY_BIN}" ] && [ -f "${LEGENDARY_BIN}" ]; then
    legendary_bin="${LEGENDARY_BIN}"
  else
    legendary_bin="/opt/Heroic/resources/app.asar.unpacked/build/bin/linux/legendary"
  fi

  if [ ! -f  "${legendary_bin}" ]; then
    legendary_bin="$($which legendary)"
  fi

  if [ ! -f  "${legendary_bin}" ]; then
    showMessage "Legendary executable not found." "e"
    exit
  fi

  if [ -z "$(${legendary_bin} -V | $grep "^legendary version")" ]; then
    showMessage "Specified binary \"${LEGENDARY_BIN}\" was not recognized as Legendary Launcher.\n\
  Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH." "e"
    exit
  fi

  if [ "$( $ldd "${legendary_bin}" 2>&1 | $grep -c "not a dynamic executable" )" -ne 0 ]; then
    showMessage "Legendary executable is a python script and it cannot run inside Steam Linux Runtime Environment.\n\
  Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH." "e"
    exit
  fi
}

get_installed_games() {
  if [ -z "${LEGENDARY_INSTALLED_GAMES}" ]; then
    LEGENDARY_INSTALLED_GAMES="$( PYTHONHOME="${PYTHONHOME}" PYTHONPATH="${PYTHONPATH}" LC_ALL=C.UTF-8 ${legendary_bin} list-installed --show-dirs --check-updates --csv 2>/dev/null| tr -d "\r" | $sed '1d' )"
  fi
}

app_name_from_app_dir(){
  if [ -n "$1" ]; then
    get_installed_games
    echo -n "$( echo -n "${LEGENDARY_INSTALLED_GAMES}" | $cut -d "," -f 1,7 | $grep ",${1}$" | $tr -d '\n' | $cut -d "," -f 1)"
  fi
}

app_id_from_title(){
  if [ -n "$1" ]; then
    get_installed_games
    echo -n "$( echo -n "${LEGENDARY_INSTALLED_GAMES}" | $cut -d "," -f 1,2 | $grep ",${1}$" | $tr -d '\n' | $cut -d "," -f 1)"
  fi
}

app_dir_from_title(){
  if [ -n "$1" ]; then
    get_installed_games
    echo -n "$( echo -n "${LEGENDARY_INSTALLED_GAMES}" | $cut -d "," -f 2,7 | $grep "^${1}," | $tr -d '\n' | $cut -d "," -f 2)"
  fi
}

app_update_from_app_id(){
  if [ -n "$1" ]; then
    get_installed_games
    echo -n "$( echo -n "${LEGENDARY_INSTALLED_GAMES}" | $cut -d "," -f 1,5 | $grep "^${1}," | $tr -d '\n' | $cut -d "," -f 2)"
  fi
}

check_for_updates(){
  if [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ]; then
    if [ "$( app_update_from_app_id "${1}" )" == "True" ]; then
      askQuestion "Game \"${2}\" has a new version availabe.\nUpdate it before start the game?"
      response=$?
      if [ $response -eq 0 ]; then
        do_game_updates "${1}" "${2}"
      else
        showMessage "Game is out of date, please update or launch with update check skipping!" "e"
        exit
      fi
    fi
  fi
}

do_game_updates(){
  if [ $# -eq 2 ] && [ -n "$1" ] && [ -n "$2" ]; then
    ( ${legendary_bin} install --repair-and-update-only --force -y "${1}" 2>&1 | while read -r line ; do
     echo "$line" | $sed -ne "s/^\[DLManager\] INFO: = Progress: \(.*\)%.*, ETA: \(.*\)/\1\n#Remaining: \2/p"
    done | $zenity --progress --width=240 --title "Updating ${2}" --window-icon=info --auto-close 2>/dev/null &
    zenity_pid="$!"
    zenity_cmd="$($cat /proc/${zenity_pid}/cmdline 2>&1 | tr "\0" " ")"
    legendary_pid="$(jobs -p 2>/dev/null)"
    legendary_cmd="$($cat /proc/${legendary_pid}/cmdline 2>&1 | tr "\0" " ")"
    while [ -f "/proc/${zenity_pid}/cmdline" ] && [ "$($cat /proc/${zenity_pid}/cmdline 2>&1 | tr "\0" " ")" == "${zenity_cmd}" ]; do
      sleep 0.5
    done
    if [ -f "/proc/${legendary_pid}/cmdline" ] && [ "$($cat /proc/${legendary_pid}/cmdline 2>&1 | tr "\0" " ")" == "${legendary_cmd}" ]; then
      disown "${legendary_pid}"
      legendary_gpid="$($cat /proc/${legendary_pid}/stat | $cut -d " " -f 5)"
      if [ -n "${legendary_gpid}" ] && [ "${legendary_gpid}" != "0" ]; then
        kill -SIGTERM -- -${legendary_gpid}
      fi
    fi )
  fi
}

set_brightness(){
  if [ "${BRIGHTNESS}" -eq "${BRIGHTNESS}" ] 2>/dev/null ; then
    if [ "${BRIGHTNESS}" -ge 0 ] && [ "${BRIGHTNESS}" -le 100 ]; then
      monitor_brightness="$(LC_NUMERIC=C $printf "%0.2f" "${BRIGHTNESS}e-2")"
    fi
  fi
}

set_steam_vars(){
  local PROTON_STANDARD_PATHS
  local STEAM_LIBRARY_FOLDER_FILE

  if [ -n "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ] && [ -d "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
    STEAM_ROOT="$($readlink -f "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" )"
  else
    if [ -e "${HOME}/.steam/root" ]; then
      STEAM_ROOT="$($readlink "${HOME}/.steam/root" )"
    elif [ -e "${HOME}/.local/share/Steam" ]; then
      STEAM_ROOT="$($readlink "${HOME}/.local/share/Steam")"
    else
      showMessage "Error: Unable to locate Steam root path." "e"
      exit
    fi
  fi

  PROTON_CUSTOM_BASEDIR=()
  PROTON_STANDARD_PATHS=( "${STEAM_ROOT}/compatibilitytools.d" "/usr/share/steam/compatibilitytools.d" "/usr/local/share/steam/compatibilitytools.d" )
  for proton_folder in "${PROTON_STANDARD_PATHS[@]}"; do
    if [ -d "${proton_folder}" ]; then
      PROTON_CUSTOM_BASEDIR+=( "$proton_folder" )
    fi
  done
  if [ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS}" ]; then
    while IFS=":" read -ra folder_array; do
      for folder in "${folder_array[@]}"; do
        if [ -d "$folder" ]; then
          PROTON_CUSTOM_BASEDIR+=( "$folder" )
        fi
      done
    done <<< "$(echo -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS}")" 
  fi

  STEAM_LIBRARY_FOLDERS=( "${STEAM_ROOT}/steamapps" )
  STEAM_LIBRARY_FOLDER_FILE="${STEAM_ROOT}/steamapps/libraryfolders.vdf"
  if [ -f "${STEAM_LIBRARY_FOLDER_FILE}" ]; then
    while read -r folder; do
      if [ -n "$folder" ] && [ -d "$folder/steamapps" ]; then
        STEAM_LIBRARY_FOLDERS+=( "${folder}/steamapps" )
      fi
    done <<< "$($sed -ne "s/.*\"[[:digit:]]\+\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LIBRARY_FOLDER_FILE}")"
  fi

  if [ -z "$zenity" ]; then
    HOST_ARCH=i386
    if [ "${CPU}" == "x86_64" ]; then
      HOST_ARCH="amd64"
    fi
    if [ -x "${STEAM_ROOT}/ubuntu12_32/steam-runtime/${HOST_ARCH}/usr/bin/zenity" ]; then
      zenity="${STEAM_ROOT}/ubuntu12_32/steam-runtime/${HOST_ARCH}/usr/bin/zenity"
    fi
  fi
}

proton_basedir_from_version(){
  local PROTON_ACF
  local PROTON_DIR
  local PROTON_INSTALLDIR
  local PROTON_CUSTOM_VDF

  if [ $# -eq 1 ] && [ -n "${1}" ]; then
    local PROTON_VER="${1}"
    PROTON_ACF="$($grep -l "\"${PROTON_VER}\"" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat )"
    if [ -n "${PROTON_ACF}" ] && [ -f "${PROTON_ACF}" ]; then
      PROTON_DIR="$( $dirname "$(echo -n "${PROTON_ACF}")" )"
      PROTON_INSTALLDIR="$($sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${PROTON_ACF}")"
      PROTON_BASEDIR="${PROTON_DIR}/common/${PROTON_INSTALLDIR}"
    else
      for folder in "${PROTON_CUSTOM_BASEDIR[@]}"; do
        PROTON_CUSTOM_VDF="$($grep -l "\"${PROTON_VER}\"" "${folder}"/*/compatibilitytool.vdf)"
        if [ -f "${PROTON_CUSTOM_VDF}" ]; then
          PROTON_BASEDIR="$( $dirname "$(echo -n "${PROTON_CUSTOM_VDF}")" )"
          break
        fi
      done
    fi

    if [ ! -d "${PROTON_BASEDIR}" ]; then
      showMessage "Proton version \"${PROTON_VER}\" not found." "e"
      exit
    fi
  else
    showMessage "Proton version not specified." "e"
    exit
  fi

}

steam_linux_runtime_bin_from_version(){
  local STEAM_LINUX_RUNTIME_ACF
  local STEAM_LINUX_RUNTIME_INSTALLDIR
  local steamLinuxRuntime_manifest
  local steamLinuxRuntime_commandLine

  if [ $# -eq 1 ] && [ -n "${1}" ]; then
    local STEAM_LINUX_RUNTIME="${1}"

    STEAM_LINUX_RUNTIME_ACF="$($grep -l "\"name\"[[:space:]]\+\"${STEAM_LINUX_RUNTIME}\"" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat )"
    STEAM_LINUX_RUNTIME_INSTALLDIR="$($sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LINUX_RUNTIME_ACF}")"
    STEAM_LINUX_RUNTIME_BASEDIR="$( $dirname "$(echo -n "${STEAM_LINUX_RUNTIME_ACF}")" )/common/${STEAM_LINUX_RUNTIME_INSTALLDIR}"

    steamLinuxRuntime_manifest="${STEAM_LINUX_RUNTIME_BASEDIR}/toolmanifest.vdf"

    if [ ! -f "${steamLinuxRuntime_manifest}" ]; then
      showMessage "Missing \"toolmanifest.vdf\" for \"${STEAM_LINUX_RUNTIME}\"" "e"
      exit
    else
      steamLinuxRuntime_commandLine="$( $grep "\"commandline\"[[:space:]]\+\"[^\"]\+\"" "${steamLinuxRuntime_manifest}" | $cut -d "\"" -f 4 | $cut -d " " -f 1)"
      if [ -z "${steamLinuxRuntime_commandLine}" ]; then
        showMessage "Unable to get Steam Linux Runtime command line." "e"
        exit
      fi
    fi
  
    steamLinuxRuntime_bin="${STEAM_LINUX_RUNTIME_BASEDIR}/${steamLinuxRuntime_commandLine}"
    if [ ! -f  "${steamLinuxRuntime_bin}" ]; then
      showMessage "Runtime \"${STEAM_LINUX_RUNTIME}\" not found." "e"
      exit
    fi
  else
    showMessage "Steam Linux Runtime version not specified." "e"
    exit
  fi
}

set_proton_version(){
  if [ -n "${PROTON_VER}" ]; then
    case "${PROTON_VER}" in
      "latest-stable"|"latest stable"|"latest-GE"|"latest GE"|"experimental")
      PROTON_VERSION="${PROTON_VER}"
      PROTON_VER=""
    esac
  fi
  if [ -z "${PROTON_VER}" ]; then
    if [ -z "${PROTON_VERSION}" ]; then
      PROTON_VERSION="latest stable"
    fi
    case "${PROTON_VERSION}" in
      "latest-stable"|"latest stable")
        latest_stable="$($grep -h "\"name\"[[:space:]]\+\"Proton [[:digit:]]\+.[[:digit:]]\+" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat | $cut -d "\"" -f 4 | $sort --version-sort -r | $head -n 1 )"
        if [ -n "${latest_stable}" ]; then
          PROTON_VER="${latest_stable}"
        fi
      ;;
      "experimental")
        PROTON_VER="Proton Experimental"
      ;;
      "latest GE"|"latest-GE")
        latest_ge="$($grep -h "^[[:space:]]\+\"Proton-[[:digit:]]\+.[[:digit:]]\+-GE-[[:digit:]]\+\"" $( $printf '%s/*/compatibilitytool.vdf' ${PROTON_CUSTOM_BASEDIR[@]} ) | $cut -d "\"" -f 2 | $sort -r --version-sort --field-separator=- | $head -n 1)"
        if [ -n "${latest_ge}" ]; then
          PROTON_VER="${latest_ge}"
        fi
      ;;
      *)
        PROTON_VER="${PROTON_VERSION}"
      ;;
    esac
  fi
}

set_steam_linux_runtime_version(){
  if [ -z "${STEAM_LINUX_RUNTIME}" ]; then
    if [ -n "${STEAM_LINUX_RUNTIME_VERSION}" ]; then
      STEAM_LINUX_RUNTIME="${STEAM_LINUX_RUNTIME_VERSION}"
    else
      STEAM_LINUX_RUNTIME="Steam Linux Runtime - Soldier"
    fi
  fi
}

export_steam_compat_vars(){
  local GAME_OVERLAY_LIBS="${STEAM_ROOT}/ubuntu12_32/gameoverlayrenderer.so:${STEAM_ROOT}/ubuntu12_64/gameoverlayrenderer.so"

  if [ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
    export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_ROOT}"
  fi

  export STEAM_COMPAT_INSTALL_PATH=$GAME_DIR
  export STEAM_COMPAT_DATA_PATH="${PREFIX_BASEDIR}/${GAME_BASENAME}"
  export WINEDLLPATH="${PROTON_BASEDIR}/files/lib64/wine:${PROTON_BASEDIR}/files/lib/wine"

  if [[ "${legendary_bin}" =~ ^/(usr)/.* ]]; then
    legendary_bin="/run/host${legendary_bin}"
  else
    export PRESSURE_VESSEL_FILESYSTEMS_RO="${legendary_bin}"
  fi

  if [[ ! ${PROTON_BASEDIR} =~ ^${HOME} ]] && [[ ${PROTON_BASEDIR} =~ .*/compatibilitytools.d/.* ]]; then
    if [ -z "${PRESSURE_VESSEL_FILESYSTEMS_RO}" ]; then
      delimiter=""
    else
      delimiter=":"
    fi
    export PRESSURE_VESSEL_FILESYSTEMS_RO="${PRESSURE_VESSEL_FILESYSTEMS_RO}${delimiter}${PROTON_BASEDIR}"
  fi
  if [[ ! ${STEAM_COMPAT_INSTALL_PATH} =~ ^${HOME} ]]; then
    export STEAM_COMPAT_MOUNTS="${STEAM_COMPAT_INSTALL_PATH}"
  fi

  if [ "$( isInSteam )" -eq 0 ]; then
    SteamPVSocket="$( $find /tmp -type d -name -name "SteamPVSocket.*" -user ${UID} > /dev/null )"
    if [ -n  "${SteamPVSocket}" ]; then
      export PRESSURE_VESSEL_SOCKET_DIR="${SteamPVSocket}"
    fi
  else
    if [ -n "${LD_PRELOAD}" ]; then
      export LD_PRELOAD="${LD_PRELOAD}:${GAME_OVERLAY_LIBS}"
    else
      export LD_PRELOAD="${GAME_OVERLAY_LIBS}"
    fi
  fi

  export STEAM_COMPAT_TOOL_PATHS="${PROTON_BASEDIR}:${STEAM_LINUX_RUNTIME_BASEDIR}"
  export PRESSURE_VESSEL_BATCH=1
  export PRESSURE_VESSEL_GC_LEGACY_RUNTIMES=1
  export PRESSURE_VESSEL_RUNTIME_BASE="${STEAM_LINUX_RUNTIME_BASEDIR}"
  if [ -d "${STEAM_LINUX_RUNTIME_BASEDIR}/var" ]; then
    export PRESSURE_VESSEL_VARIABLE_DIR="${STEAM_LINUX_RUNTIME_BASEDIR}/var"
  fi
  export STEAM_COMPAT_LIBRARY_PATHS="${STEAM_COMPAT_TOOL_PATHS}:${STEAM_COMPAT_INSTALL_PATH}"
  if [ -z "${SteamGameId}" ]; then
    export SteamGameId=0
  fi
  if [ -z "${SteamOverlayGameId}" ]; then
    export SteamOverlayGameId=0
  fi
}

list_proton_versions(){
  local PROTON_VERSIONS
  
  PROTON_VERSIONS="$($grep -h "\"name\"[[:space:]]\+\"Proton.*\"" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat | $cut -d "\"" -f 4)"
  for folder in "${PROTON_CUSTOM_BASEDIR[@]}"; do
    PROTON_VERSIONS="${PROTON_VERSIONS}\n$($sed -e '/^[[:blank:]]*\/\//d;s/\/\/.*//' "${folder}"/*/compatibilitytool.vdf | $tr "\n" " " | $grep -o "\"compat_tools\"[^{]*{[^\"]*\"[^\"]\+\"" | $cut -d "{" -f 2 | $sed -ne "s/^[^\"]*\"\([^\"]\+\)\".*/\1/p")"
  done
  PROTON_VERSIONS="$(echo -e "${PROTON_VERSIONS}")"
  if [ -n "${PROTON_VER}" ]; then
    echo "Default: ${PROTON_VER}"
  fi
  echo "${PROTON_VERSIONS}" | $sort --version-sort
}

list_runtime_versions(){
  local STEAM_LINUX_RUNTIME_VERSIONS

  STEAM_LINUX_RUNTIME_VERSIONS="$($grep -h "\"name\"[[:space:]]\+\"Steam Linux Runtime[^\"]*\"" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat | cut -d "\"" -f 4 | sort)"
  if [ -n "${STEAM_LINUX_RUNTIME}" ]; then
    echo "Default: ${STEAM_LINUX_RUNTIME}"
  fi
  echo "${STEAM_LINUX_RUNTIME_VERSIONS}"
}

pause_desktop_effects(){
  if [ -z "${DISABLE_DESKTOP_EFFECTS}" ] || [ "${DISABLE_DESKTOP_EFFECTS}" == "1" ]; then
    case "${XDG_SESSION_DESKTOP}" in
      KDE)
        if [ -n "${qdbus}" ]; then
          if [ "$($qdbus org.kde.KWin /Compositor org.kde.kwin.Compositing.active)" == "true" ]; then
            DESKTOP_EFFECTS_RESUME=1
            $qdbus org.kde.KWin /Compositor suspend
          fi
        fi
        ;;
      GNOME)
        if [ -n "${gsettings}" ]; then
          if [ "$($gsettings get org.gnome.desktop.interface enable-animations)" == "true" ]; then
            DESKTOP_EFFECTS_RESUME=1
            $gsettings set org.gnome.desktop.interface enable-animations false
          fi
        fi
        ;;
      *)
        ;;
    esac
  fi
}

turn_off_the_lights(){
  if [ -z "${TURN_OFF_THE_LIGHTS}" ] || [ "${TURN_OFF_THE_LIGHTS}" == "1" ]; then
    if [ -n "${monitor_sh}" ] && [ -n "${monitor_brightness}" ]; then
      ${monitor_sh} -p -b "${monitor_brightness}"
    fi
  fi
}

turn_on_the_lights(){
  if [ -z "${TURN_OFF_THE_LIGHTS}" ] || [ "${TURN_OFF_THE_LIGHTS}" == "1" ]; then
    if [ -n "${monitor_sh}" ]; then
      ${monitor_sh} on
    fi
  fi
}

resume_desktop_effects(){
  if [ -z "${DISABLE_DESKTOP_EFFECTS}" ] || [ "${DISABLE_DESKTOP_EFFECTS}" == "1" ]; then
    if [ $DESKTOP_EFFECTS_RESUME -eq 1 ]; then
      case "${XDG_SESSION_DESKTOP}" in
        KDE)
          if [ -n "${qdbus}" ]; then
            $qdbus org.kde.KWin /Compositor resume
          fi
        ;;
        GNOME)
          if [ -n "${gsettings}" ]; then
            $gsettings set org.gnome.desktop.interface enable-animations true
          fi
        ;;
        *)
        ;;
      esac
    fi
  fi
}

failure() {
  local lineno="$1"
  local msg="$2"
  showMessage "Failed at $lineno: $msg" "d"
}

if [ "${DEBUG}" == "1" ]; then
  set -eE -o functrace
  trap 'failure ${LINENO} "$BASH_COMMAND"' ERR
fi

set_commands
set_steam_vars

BRIGHTNESS=10

CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
CONFIG_DIR="${CONFIG_HOME}/steam-legendary-wrapper"

if [ -d "${HOME}/.config" ]; then
  if [ ! -e "${CONFIG_DIR}" ]; then
    $mkdir "${CONFIG_DIR}"
  fi

  if [ -f "${CONFIG_DIR}/config" ]; then
    . "${CONFIG_DIR}/config"
  fi
  if [ -f "${CONFIG_DIR}/games/${APP_ID}" ]; then
    . "${CONFIG_DIR}/games/${APP_ID}"
    if [ "${DEBUG}" == "1" ]; then
      showMessage "Loaded configuration from ${CONFIG_DIR}/games/${APP_ID}" "d"
    fi
  fi
fi

if [ "$#" -eq 1 ]; then
  case "${1}" in
    "list-proton-versions")
      set_proton_version
      list_proton_versions
    exit
    ;;
    "list-runtime-versions")
      set_steam_linux_runtime_version
      list_runtime_versions
    exit
    ;;
    *)
    ;;
  esac
fi

declare -a STEAM_LIBRARY_FOLDERS
declare -a GAME_PARAMS
declare -a GAME_PARAMS_PRE
PROTON_RUN="waitforexitandrun"
GAME_NAME=""
COMPAT_TOOL=0
DESKTOP_EFFECTS_RESUME=0
LEGENDARY_INSTALLED_GAMES=""
GAME_PARAMS_SEPARATOR=""

legendary_config="${HOME}/.config/legendary/config.ini"

set_brightness
set_language
set_python_vars
find_legendary_bin

command_line_parse "$@"

if [ -n "${APP_ID}" ] && [ -n "${GAME_DIR}" ]; then
  check_for_updates "${APP_ID}" "${GAME_NAME}"
  set_proton_version
  set_steam_linux_runtime_version

  proton_basedir_from_version "${PROTON_VER}"
  steam_linux_runtime_bin_from_version "${STEAM_LINUX_RUNTIME}"

  GAME_BASENAME="$($basename "${GAME_DIR}")"
  GAME_DIRNAME="$($dirname "${GAME_DIR}")"
  PREFIX_BASEDIR="${GAME_DIRNAME}/WinePrefix"
  if [ ! -d "${PREFIX_BASEDIR}/${GAME_BASENAME}" ]; then
    $mkdir -p "${PREFIX_BASEDIR}/${GAME_BASENAME}"
  fi

  export_steam_compat_vars

  pause_desktop_effects
  turn_off_the_lights
 
  ${steamLinuxRuntime_bin} -- sh -c 'PYTHONHOME="$( dirname "$(echo -n "$( which python3 )" )" )" PYTHONPATH="$( python3 -c "import sys;print('\'':'\''.join(map(str, list(filter(None, sys.path)))))" )" '"${GAME_PARAMS_PRE[*]} ${legendary_bin} launch \"${APP_ID}\" ${language} --no-wine --wrapper \"'${PROTON_BASEDIR}/proton' ${PROTON_RUN}\" ${GAME_PARAMS_SEPARATOR} ${GAME_PARAMS[*]}"

  turn_on_the_lights
  resume_desktop_effects
fi
