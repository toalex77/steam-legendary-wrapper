#!/bin/bash
# TODO:
#   - add options to list Proton and Steam Linux Runtime versions (show in zenity/notify-send if inside steam, otherwise echo to stdout)
#   - Manage GAME_PARAMS when not run as a compatility tool
#   - Manage GAME_PARAMS 
#   - Add game directory to PRESSURE_VESSEL_FILESYSTEMS_RO when it is not reacheable inside the Steam Linux Runtime
#   - Per game configuration
#   - Less procedural, more functions
#   - Create initial configuration file if missing
#   - Install as compatibility tool, if required by user
#   - Check for game updates (legendary list-installed --check-updates - 5th column) and notify user
#   - Check for used external tools at startup

zenity="$(which zenity 2>/dev/null)"
notifysend="$(which notify-send 2>/dev/null)"

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
  if [ -n "${zenity}" ]; then
    $zenity "${LEVEL_ARRAY[1]}" --text="$message" --title="${title}" --width=240
  elif [ -n "${notifysend}" ]; then
    $notifysend -u normal "${LEVEL_ARRAY[2]}" "$title" "$message"
  else
    echo "${title}"
    echo "${LEVEL_ARRAY[0]}: ${message}"
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

CONFIG_HOME="${HOME}/.config"
CONFIG_DIR="${CONFIG_HOME}/steam-legendary-wrapper"

if [ -d "${HOME}/.config" ]; then
  if [ ! -e "${CONFIG_DIR}" ]; then
    mkdir "${CONFIG_DIR}"
  fi

  if [ -f "${CONFIG_DIR}/config" ]; then
    . "${CONFIG_DIR}/config"
  fi
fi

declare -a STEAM_LIBRARY_FOLDERS
PROTON_RUN="waitforexitandrun"
GAME_NAME=""
GAME_PARAMS=""
COMPAT_TOOL=0

legendary_config="${HOME}/.config/legendary/config.ini"

if [ -n "${LANGUAGE}" -a -n "$(locale -a | grep "^${LANGUAGE:0:2}")" ]; then
  language="--language ${LANGUAGE:0:2}"
else
  if [ ! -f "${legendary_config}" -o "$( grep -c locale "${legendary_config}" 2> /dev/null )" == "0" ]; then # "fix Kate Syntax Highlight
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

python3_bin="$(which python3)"
if [ ! -f  "${python3_bin}" ]; then
  showMessage "Python 3 executable not found." "e"
  exit
fi
PYTHONPATH="$( $python3_bin -c "import sys;print(':'.join(map(str, list(filter(None, sys.path)))))" )"
PYTHONHOME="$( dirname "$(echo -n "${python3_bin}")" )"

if [ -n "${LEGENDARY_BIN}" -a -f "${LEGENDARY_BIN}" ]; then
  if [ -n "$(${LEGENDARY_BIN} -V | grep "^legendary version")" ]; then
    legendary_bin="${LEGENDARY_BIN}"
  else
    showMessage "Specified binary \"${LEGENDARY_BIN}\" was not recognized as Legendary Launcher.\n\
Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH." "e"
  fi
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

if [ "$( ldd "${legendary_bin}" 2>&1 | grep -c "not a dynamic executable" )" -ne 0 ]; then
   showMessage "Legendary executable is a python script and it cannot run inside Steam Linux Runtime Environment.\n\
Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH." "e"
   exit
fi

# TODO: Manage GAME_PARAMS when not run as a compatility tool
if [ -n "$1" -a -n "$2" ]; then
  if [ "$1" == "compatrun" -o "$1" == "compatwaitforexitandrun" ]; then
    PROTON_RUN="${1#*compat}"
    APPDIR="$(dirname "${2}")"
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
    LEGENDARY_LINE="$(PYTHONHOME="${PYTHONHOME}" PYTHONPATH="${PYTHONPATH}" LC_ALL=C.UTF-8 ${legendary_bin} list-installed --show-dirs --csv | cut -d "," -f 1,7 | grep "${APPDIR}" | tr -d '\n\r')"
    GAME_NAME="$(echo -n "${LEGENDARY_LINE}" | cut -d "," -f 1)"
    COMPAT_TOOL=1
  fi
fi

if [ -n "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" -a -d "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
  STEAM_ROOT="$(readlink -f "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" )"
else
  if [ -e "${HOME}/.steam/root" ]; then
    STEAM_ROOT="$(readlink "${HOME}/.steam/root" )"
  elif [ -e "${HOME}/.local/share/Steam" ]; then
    STEAM_ROOT="${HOME}/.local/share/Steam"
  else
    showMessage "Error: Unable to locale Steam root path." "e"
    exit
  fi
fi

STEAM_LIBRARY_FOLDERS=( "${STEAM_ROOT}/steamapps" )
STEAM_LIBRARY_FOLDER_FILE="${STEAM_ROOT}/steamapps/libraryfolders.vdf"

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

if [ -f "${STEAM_LIBRARY_FOLDER_FILE}" ]; then
  while read -r folder; do
    if [ -n "$folder" -a -d "$folder/steamapps" ]; then
      STEAM_LIBRARY_FOLDERS+=( "${folder}/steamapps" )
    fi
  done <<< "$(sed -ne "s/.*\"[[:digit:]]\+\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LIBRARY_FOLDER_FILE}")"
fi

if [ $COMPAT_TOOL -eq 0 ]; then
  if [ -z "${GAME_NAME}" -a $# -ge 1 ]; then
    GAME_NAME="$1"
  fi
  if [ -z "${PROTON_VER}" -a $# -ge 2 ]; then
    PROTON_VER="$2"
  fi
  if [ -z "${STEAM_LINUX_RUNTIME}" -a $# -ge 3 ]; then
    STEAM_LINUX_RUNTIME="$3"
  fi
fi

if [ -n "${GAME_NAME}" ]; then

  if [ -z "${PROTON_VER}" ]; then
    if [ -z "${PROTON_VERSION}" ]; then
      PROTON_VERSION="latest stable"
    fi
    case "${PROTON_VERSION}" in
      "latest stable")
        latest_stable="$(grep -h "\"name\"[[:space:]]\+\"Proton [[:digit:]]\+.[[:digit:]]\+" $( printf '%s/*.acf ' "${STEAM_LIBRARY_FOLDERS[@]}" ) | cut -d "\"" -f 4 | sort --version-sort -r | head -n 1 )"
        if [ -n "${latest_stable}" ]; then
          PROTON_VER="${latest_stable}"
        fi
      ;;
      "experimental")
        PROTON_VER="Proton Experimental"
      ;;
      "latest GE")
        latest_ge="$(grep -h "^[[:space:]]\+\"Proton-[[:digit:]]\+.[[:digit:]]\+-GE-[[:digit:]]\+\"" $( printf '%s/*/compatibilitytool.vdf' "${PROTON_CUSTOM_BASEDIR[@]}") | cut -d "\"" -f 2 | sort -r --version-sort --field-separator=- | head -n 1)"
        if [ -n "${latest_ge}" ]; then
          PROTON_VER="${latest_ge}"
        fi
      ;;
      *)
        PROTON_VER="${PROTON_VERSION}"
      ;;
    esac
  fi

  if [ -z "${STEAM_LINUX_RUNTIME}" ]; then
    if [ -n "${STEAM_LINUX_RUNTIME_VERSION}" ]; then
      STEAM_LINUX_RUNTIME="${STEAM_LINUX_RUNTIME_VERSION}"
    else
      STEAM_LINUX_RUNTIME="Steam Linux Runtime - Soldier"
    fi
  fi

  PROTON_ACF="$(grep -l "\"${PROTON_VER}\"" $( printf '%s/*.acf ' "${STEAM_LIBRARY_FOLDERS[@]}" ) )"
  if [ -n "${PROTON_ACF}" -a -f "${PROTON_ACF}" ]; then
    PROTON_DIR="$( dirname "$(echo -n "${PROTON_ACF}")" )"
    PROTON_INSTALLDIR="$(sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${PROTON_ACF}")"
    PROTON_BASEDIR="${PROTON_DIR}/common/${PROTON_INSTALLDIR}"
  else
    for folder in "${PROTON_CUSTOM_BASEDIR[@]}"; do
      PROTON_CUSTOM_VDF="$(grep -l "\"${PROTON_VER}\"" "${folder}"/*/compatibilitytool.vdf)"
      if [ -f "${PROTON_CUSTOM_VDF}" ]; then
        PROTON_BASEDIR="$( dirname "$(echo -n "${PROTON_CUSTOM_VDF}")" )"
        break
      fi
    done
  fi

  if [ ! -d "${PROTON_BASEDIR}" ]; then
    showMessage "Proton version \"${PROTON_VER}\" not found." "e"
    exit
  fi
  
  STEAM_LINUX_RUNTIME_ACF="$(grep -l "\"name\"[[:space:]]\+\"${STEAM_LINUX_RUNTIME}\"" $( printf '%s/*.acf ' "${STEAM_LIBRARY_FOLDERS[@]}" ) )"
  STEAM_LINUX_RUNTIME_BASEDIR="$( dirname "$(echo -n "${STEAM_LINUX_RUNTIME_ACF}")" )"
  STEAM_LINUX_RUNTIME_INSTALLDIR="$(sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LINUX_RUNTIME_ACF}")"

  steamLinuxRuntime_manifest="${STEAM_LINUX_RUNTIME_BASEDIR}/common/${STEAM_LINUX_RUNTIME_INSTALLDIR}/toolmanifest.vdf"
  if [ ! -f "${steamLinuxRuntime_manifest}" ]; then
    showMessage "Missing \"toolmanifest.vdf\" for \"${STEAM_LINUX_RUNTIME}\"" "e"
    exit
  else
    steamLinuxRuntime_commandLine="$( grep "\"commandline\"[[:space:]]\+\"[^\"]\+\"" "${steamLinuxRuntime_manifest}" | cut -d "\"" -f 4 | cut -d " " -f 1)"
    if [ -z "${steamLinuxRuntime_commandLine}" ]; then
      showMessage "Unable to get Steam Linux Runtime command line." "e"
      exit
    fi
  fi
  
  steamLinuxRuntime_bin="${STEAM_LINUX_RUNTIME_BASEDIR}/common/${STEAM_LINUX_RUNTIME_INSTALLDIR}${steamLinuxRuntime_commandLine}"
  if [ ! -f  "${steamLinuxRuntime_bin}" ]; then
    showMessage "Runtime \"${STEAM_LINUX_RUNTIME}\" not found." "e"
    exit
  fi

  LEGENDARY_LINE="$(PYTHONHOME="${PYTHONHOME}" PYTHONPATH="${PYTHONPATH}" LC_ALL=C.UTF-8 ${legendary_bin} list-installed --show-dirs --tsv | grep "${GAME_NAME}" | tr -d '\n\r')"
  
  if [ "${LEGENDARY_LINE}" != "" ]; then
    EPIC_GAME_NAME="$(echo -n "${LEGENDARY_LINE}" | cut -f 1)"
    GAME_DIR="$(echo -n "${LEGENDARY_LINE}" | cut -f 7)"

    GAME_BASENAME="$(basename "$(echo -n "${GAME_DIR}")")"

    GAME_DIRNAME="$(dirname "$(echo -n "${GAME_DIR}")")"
    PREFIX_BASEDIR="${GAME_DIRNAME}/WinePrefix"

    if [ -z "${STEAM_COMPAT_CLIENT_INSTALL_PATH}" ]; then
      export STEAM_COMPAT_CLIENT_INSTALL_PATH=${HOME}/.steam/steam
    fi
    export STEAM_COMPAT_DATA_PATH="${PREFIX_BASEDIR}/${GAME_BASENAME}"
    export WINEDLLPATH="${PROTON_BASEDIR}/files/lib64/wine:${PROTON_BASEDIR}/files/lib/wine"

    if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
      mkdir -p "${STEAM_COMPAT_DATA_PATH}"
    fi

    if [[ "${legendary_bin}" =~ ^/(usr)/.* ]]; then
      legendary_bin="/run/host${legendary_bin}"
    else
      export PRESSURE_VESSEL_FILESYSTEMS_RO="${legendary_bin}"
    fi
    if [ -z "${DISABLE_DESKTOP_EFFECTS}" -o "${DISABLE_DESKTOP_EFFECTS}" == "1" ]; then
      resume=0
      case "${XDG_SESSION_DESKTOP}" in
        KDE)
          if [ "$(qdbus org.kde.KWin /Compositor org.kde.kwin.Compositing.active)" == "true" ]; then
            resume=1
            qdbus org.kde.KWin /Compositor suspend
          fi
          ;;
        GNOME)
          if [ "$(gsettings get org.gnome.desktop.interface enable-animations)" == "true" ]; then
            resume=1
            gsettings set org.gnome.desktop.interface enable-animations false
          fi
          ;;
        *)
          ;;
      esac
    fi
    if [ -z "${TURN_OFF_THE_LIGHTS}" -o "${TURN_OFF_THE_LIGHTS}" == "1" ]; then
      monitor_sh="$(which monitor.sh 2>/dev/null)"
      if [ -n "${monitor_sh}" ]; then
        ${monitor_sh} -p -b 0.1
      fi
    fi

    if [[ ! ${PROTON_BASEDIR} =~ ^${HOME} ]]; then
      if [ -z "${PRESSURE_VESSEL_FILESYSTEMS_RO}" ]; then
        delimiter=""
      else
        delimiter=":"
      fi
      export PRESSURE_VESSEL_FILESYSTEMS_RO="${PRESSURE_VESSEL_FILESYSTEMS_RO}${delimiter}${PROTON_BASEDIR}"
    fi

    # TODO: Manage GAME_PARAMS
    ${steamLinuxRuntime_bin} -- sh -c 'PYTHONHOME="$( dirname "$(echo -n "$( which python3 )" )" )" PYTHONPATH="$( python3 -c "import sys;print('\'':'\''.join(map(str, list(filter(None, sys.path)))))" )" '"${legendary_bin} launch \"${EPIC_GAME_NAME}\" ${language} --no-wine --wrapper \"'${PROTON_BASEDIR}/proton' ${PROTON_RUN}\""
    
    if [ -z "${TURN_OFF_THE_LIGHTS}" -o "${TURN_OFF_THE_LIGHTS}" == "1" ]; then
      if [ -n "${monitor_sh}" ]; then
        ${monitor_sh} on
      fi
    fi
    if [ -z "${DISABLE_DESKTOP_EFFECTS}" -o "${DISABLE_DESKTOP_EFFECTS}" == "1" ]; then
      if [ $resume -eq 1 ]; then
        case "${XDG_SESSION_DESKTOP}" in
          KDE)
            qdbus org.kde.KWin /Compositor resume
          ;;
          GNOME)
            gsettings set org.gnome.desktop.interface enable-animations true
          ;;
          *)
          ;;
        esac
      fi
    fi
  fi
fi
