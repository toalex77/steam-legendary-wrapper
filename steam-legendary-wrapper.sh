#!/bin/bash
# TODO:
#   - Add help
#   - Manage GAME_PARAMS when not run as a compatility tool
#   - Manage GAME_PARAMS 
#   - Add game directory to PRESSURE_VESSEL_FILESYSTEMS_RO when it is not reacheable inside the Steam Linux Runtime
#   - Create initial configuration file when missing
#   - Install as compatibility tool, if required by user
#   - Check for game updates (legendary list-installed --check-updates - 5th column) and notify user
#   - Add more and better code comments (functions, variables, configurations, ...)

set_commands(){
  basename="$(which basename 2>/dev/null)" || required "basename"
  cat="$(which cat 2>/dev/null)" || required "cat"
  cut="$(which cut 2>/dev/null)" || required "cut"
  dirname="$(which dirname 2>/dev/null)" || required "dirname"
  grep="$(which grep 2>/dev/null)" || required "grep"
  head="$(which head 2>/dev/null)" || required "head"
  locale="$(which locale 2>/dev/null)" || required "locale"
  mkdir="$(which mkdir 2>/dev/null)" || required "mkdir"
  printf="$(which printf 2>/dev/null)" || required "printf"
  python3_bin="$(which python3 2>/dev/null)" || required "python3"
  readlink="$(which readlink 2>/dev/null)" || required "readlink"
  sed="$(which sed 2>/dev/null)" || required "sed"
  sort="$(which sort 2>/dev/null)" || required "sort"
  tr="$(which tr 2>/dev/null)" || required "tr"

  gsettings="$(which gsettings 2>/dev/null)"
  monitor_sh="$(which monitor.sh 2>/dev/null)"
  notifysend="$(which notify-send 2>/dev/null)"
  qdbus="$(which qdbus 2>/dev/null)"
  zenity="$(which zenity 2>/dev/null)"
}

isInSteam() {
  if [ -n "${SteamAppUser}" ] && [ "${SteamAppId}" ]; then
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
    legendary_bin="$(which legendary)"
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

  if [ "$( ldd "${legendary_bin}" 2>&1 | $grep -c "not a dynamic executable" )" -ne 0 ]; then
    showMessage "Legendary executable is a python script and it cannot run inside Steam Linux Runtime Environment.\n\
  Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH." "e"
    exit
  fi
}

get_installed_games() {
  if [ -z "${LEGENDARY_INSTALLED_GAMES}" ]; then
    LEGENDARY_INSTALLED_GAMES="$(PYTHONHOME="${PYTHONHOME}" PYTHONPATH="${PYTHONPATH}" LC_ALL=C.UTF-8 ${legendary_bin} list-installed --show-dirs --check-updates --csv 2>/dev/null| tr -d "\r")"
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

set_brightness(){
  if [ "${BRIGHTNESS}" -eq "${BRIGHTNESS}" ] 2>/dev/null ; then
    if [ "${BRIGHTNESS}" -ge 0 ] && [ "${BRIGHTNESS}" -le 100 ]; then
      monitor_brightness="$(LC_NUMERIC=C $printf "%0.2f" "${BRIGHTNESS}e-2")"
    fi
  fi
}

set_steam_vars(){
  local STEAM_ROOT
  local PROTON_STANDARD_PATHS
  local STEAM_LIBRARY_FOLDER_FILE

  if [ -n "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ] && [ -d "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
    STEAM_ROOT="$($readlink -f "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" )"
  else
    if [ -e "${HOME}/.steam/root" ]; then
      STEAM_ROOT="$($readlink "${HOME}/.steam/root" )"
    elif [ -e "${HOME}/.local/share/Steam" ]; then
      STEAM_ROOT="$($readlink ${HOME}/.local/share/Steam)"
    else
      showMessage "Error: Unable to locate Steam root path." "e"
      exit
    fi
  fi

  # Manage correctly compatibility tools paths: https://github.com/ValveSoftware/steam-for-linux/issues/6310
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
  if [ -z "${PROTON_VER}" ]; then
    if [ -z "${PROTON_VERSION}" ]; then
      PROTON_VERSION="latest stable"
    fi
    case "${PROTON_VERSION}" in
      "latest stable")
        latest_stable="$($grep -h "\"name\"[[:space:]]\+\"Proton [[:digit:]]\+.[[:digit:]]\+" $( $printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) | $cat | $cut -d "\"" -f 4 | $sort --version-sort -r | $head -n 1 )"
        if [ -n "${latest_stable}" ]; then
          PROTON_VER="${latest_stable}"
        fi
      ;;
      "experimental")
        PROTON_VER="Proton Experimental"
      ;;
      "latest GE")
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
fi

if [ "$#" -eq 1 ]; then
  case "${1}" in
    "list-proton-versions")
      set_steam_vars
      set_proton_version
      list_proton_versions
    exit
    ;;
    "list-runtime-versions")
      set_steam_vars
      set_steam_linux_runtime_version
      list_runtime_versions
    exit
    ;;
    *)
    ;;
  esac
fi

declare -a STEAM_LIBRARY_FOLDERS
PROTON_RUN="waitforexitandrun"
GAME_NAME=""
GAME_PARAMS=""
COMPAT_TOOL=0
DESKTOP_EFFECTS_RESUME=0
LEGENDARY_INSTALLED_GAMES=""

legendary_config="${HOME}/.config/legendary/config.ini"

set_brightness
set_language
set_python_vars
find_legendary_bin

# TODO: Manage GAME_PARAMS when not run as a compatility tool
if [ -n "$1" ] && [ -n "$2" ]; then
  if [ "$1" == "compatrun" ] || [ "$1" == "compatwaitforexitandrun" ]; then
    PROTON_RUN="${1#*compat}"
    GAME_DIR="$($dirname "${2}")"
    shift 2
    GAME_PARAMS=()
    for p in "$@" ; do
      if [[ $p =~ ^PROTON_VER=.* ]]; then
        PROTON_VER="${p#"PROTON_VER="}"
      elif [[ $p =~ ^STEAM_LINUX_RUNTIME=.* ]]; then
        STEAM_LINUX_RUNTIME="${p#"STEAM_LINUX_RUNTIME="}"
      else
        GAME_PARAMS+=( "$p" )
      fi
    done
    APP_ID="$(app_name_from_app_dir "${GAME_DIR}")"
    COMPAT_TOOL=1
  fi
fi

if [ $COMPAT_TOOL -eq 0 ]; then
  if [ -z "${GAME_NAME}" ] && [ $# -ge 1 ]; then
    GAME_NAME="$1"
  fi
  if [ -z "${PROTON_VER}" ] && [ $# -ge 2 ]; then
    PROTON_VER="$2"
  fi
  if [ -z "${STEAM_LINUX_RUNTIME}" ] && [ $# -ge 3 ]; then
    STEAM_LINUX_RUNTIME="$3"
  fi
  if [ -n "${GAME_NAME}" ]; then
    APP_ID="$(app_id_from_title "${GAME_NAME}")"
    GAME_DIR="$(app_dir_from_title "${GAME_NAME}")"
  fi
fi

if [ -n "${APP_ID}" ] && [ -n "${GAME_DIR}" ]; then

  set_steam_vars

  set_proton_version
  set_steam_linux_runtime_version

  proton_basedir_from_version "${PROTON_VER}"
  steam_linux_runtime_bin_from_version "${STEAM_LINUX_RUNTIME}"

  GAME_BASENAME="$($basename "$(echo -n "${GAME_DIR}")")"

  GAME_DIRNAME="$($dirname "$(echo -n "${GAME_DIR}")")"
  PREFIX_BASEDIR="${GAME_DIRNAME}/WinePrefix"

  if [ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
    export STEAM_COMPAT_CLIENT_INSTALL_PATH=${HOME}/.steam/steam
  fi
  export STEAM_COMPAT_DATA_PATH="${PREFIX_BASEDIR}/${GAME_BASENAME}"
  export WINEDLLPATH="${PROTON_BASEDIR}/files/lib64/wine:${PROTON_BASEDIR}/files/lib/wine"

  if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
    $mkdir -p "${STEAM_COMPAT_DATA_PATH}"
  fi

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
  export STEAM_COMPAT_TOOL_PATHS="${PROTON_BASEDIR}:${STEAM_LINUX_RUNTIME_BASEDIR}"

  if [ -f "${CONFIG_DIR}/games/${APP_ID}" ]; then
    . "${CONFIG_DIR}/games/${APP_ID}"
    if [ "${DEBUG}" == "1" ]; then
      showMessage "Loaded configuration from ${CONFIG_DIR}/games/${APP_ID}" "d"
    fi
  fi

  pause_desktop_effects
  turn_off_the_lights
  # TODO: Manage GAME_PARAMS
  ${steamLinuxRuntime_bin} -- sh -c 'PYTHONHOME="$( $dirname "$(echo -n "$( which python3 )" )" )" PYTHONPATH="$( python3 -c "import sys;print('\'':'\''.join(map(str, list(filter(None, sys.path)))))" )" '"${legendary_bin} launch \"${APP_ID}\" ${language} --no-wine --wrapper \"'${PROTON_BASEDIR}/proton' ${PROTON_RUN}\""

  turn_on_the_lights
  resume_desktop_effects  
fi
