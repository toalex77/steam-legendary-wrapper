#!/bin/bash
failure() {
  local lineno=$1
  local msg=$2
  echo "Failed at $lineno: $msg"
}
if [ "${DEBUG}" == "1" ]; then
  set -eE -o functrace
  trap 'failure ${LINENO} "$BASH_COMMAND"' ERR
fi
declare -a STEAM_LIBRARY_FOLDERS
legendary_config="${HOME}/.config/legendary/config.ini"

if [ ! -f "${legendary_config}" -o "$( grep -c locale "${legendary_config}" locale 2> /dev/null )" == "0" ]; then # "fix Kate Syntax Highlight
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

if [ -e "${HOME}/.steam/root" ]; then
  STEAM_ROOT="$(readlink "${HOME}/.steam/root" )"
elif [ -e "${HOME}/.local/share/Steam" ]; then
  STEAM_ROOT="${HOME}/.local/share/Steam"
else
  echo "Error: Unable to locale Steam root path."
  exit
fi
STEAM_LIBRARY_FOLDERS=( "${STEAM_ROOT}/steamapps" )
STEAM_LIBRARY_FOLDER_FILE="${STEAM_ROOT}/steamapps/libraryfolders.vdf"

# Manage correctly compoatibility tools paths: https://github.com/ValveSoftware/steam-for-linux/issues/6310
PROTON_CUSTOM_BASEDIR=()
PROTON_STANDARD_PATHS=( "${STEAM_ROOT}/compatibilitytools.d" "/usr/share/steam/compatibilitytools.d" "/usr/local/share/steam/compatibilitytools.d" )
for proton_folder in ${PROTON_STANDARD_PATHS[@]}; do
  if [ -d "${proton_folder}" ]; then
    PROTON_CUSTOM_BASEDIR+=( "$proton_folder" )
  fi
done
if [ -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS}" ]; then
  while IFS=":" read -ra folder_array; do
    for folder in ${folder_array[@]}; do
      if [ -d "$folder" ]; then
        PROTON_CUSTOM_BASEDIR+=( "$folder" )
      fi
    done
  done <<< "$(echo -n "${STEAM_EXTRA_COMPAT_TOOLS_PATHS}")" 
fi

if [ -f "${STEAM_LIBRARY_FOLDER_FILE}" ]; then
  while read folder; do
    if [ -n "$folder" ]; then
      if [ -e "$folder/steamapps" ]; then
        if [[ ! " ${STEAM_LIBRARY_FOLDERS[@]} " =~ " ${folder}/steamapps " ]]; then
          STEAM_LIBRARY_FOLDERS+=( "${folder}/steamapps" )
        fi
      fi
    fi
  done <<< "$(sed -ne "s/.*\"[[:digit:]]\+\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LIBRARY_FOLDER_FILE}")"
fi

python3_bin="$(which python3)"
if [ ! -f  "${python3_bin}" ]; then
  echo "Python 3 executable not found."
  exit
fi

legendary_bin="/opt/Heroic/resources/app.asar.unpacked/build/bin/linux/legendary"

if [ ! -f  "${legendary_bin}" ]; then
  legendary_bin="$(which legendary)"
fi

if [ ! -f  "${legendary_bin}" ]; then
  echo "Legendary executable not found."
  exit
fi

if [ "$( ldd "${legendary_bin}" 2>&1 | grep -c "not a dynamic executable" )" -ne 0 ]; then
   echo "Legendary executable is a python script and it cannot run inside Steam Linux Runtime Environment."
   echo "Download a binary executable version from https://github.com/derrod/legendary/releases and put it in your PATH."
   exit
fi

if [ $# -ge 1 ]; then
  GAME_NAME="$1"

  if [ $# -ge 2 ]; then
    PROTON_VER="$2"
  else
    PROTON_VER="Proton-6.14-GE-2"
  fi

  PROTON_ACF="$(grep -l "\"${PROTON_VER}\"" $( printf '%s/*.acf ' ${STEAM_LIBRARY_FOLDERS[@]} ) )"
  if [ -n "${PROTON_ACF[@]}" -a -f "${PROTON_ACF[@]}" ]; then
    PROTON_DIR="$( dirname "$(echo -n "${PROTON_ACF}")" )"
    PROTON_INSTALLDIR="$(sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${PROTON_ACF}")"
    PROTON_BASEDIR="${PROTON_DIR}/common/${PROTON_INSTALLDIR}"
  else   
    for proton_folder in ${PROTON_CUSTOM_BASEDIR[@]}; do
      PROTON_CUSTOM_VDF="$(grep -l "\"${PROTON_VER}\"" ${proton_folder}/*/compatibilitytool.vdf)"
      if [ -f "${PROTON_CUSTOM_VDF}" ]; then
        PROTON_BASEDIR="$( dirname "$(echo -n "${PROTON_CUSTOM_VDF}")" )"
        break
      fi
    done
  fi

  if [ ! -d "${PROTON_BASEDIR}" ]; then
    echo "Proton version \"${PROTON_VER}\" not found."
    exit
  fi

  if [ $# -ge 3 ]; then
    STEAM_LINUX_RUNTIME="$3"
  else
    STEAM_LINUX_RUNTIME="Steam Linux Runtime - Soldier"
  fi

  STEAM_LINUX_RUNTIME_ACF="$(grep -l "\"name\"[[:space:]]\+\"${STEAM_LINUX_RUNTIME}\"" $( printf '%s/*.acf ' "${STEAM_LIBRARY_FOLDERS[@]}" ) )"
  STEAM_LINUX_RUNTIME_BASEDIR="$( dirname "$(echo -n "${STEAM_LINUX_RUNTIME_ACF}")" )"
  STEAM_LINUX_RUNTIME_INSTALLDIR="$(sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LINUX_RUNTIME_ACF}")"

  steamLinuxRuntime_bin="${STEAM_LINUX_RUNTIME_BASEDIR}/common/${STEAM_LINUX_RUNTIME_INSTALLDIR}/run"
  if [ ! -f  "${steamLinuxRuntime_bin}" ]; then
    echo "Steam Linux Runtime \"${STEAM_LINUX_RUNTIME}\" not found."
    exit
  fi
  PYTHONPATH="$( $python3_bin -c "import sys;print(':'.join(map(str, list(filter(None, sys.path)))))" )"
  PYTHONHOME="$( dirname "$(echo -n "${python3_bin}")" )"

  LEGENDARY_LINE="$(PYTHONHOME="${PYTHONHOME}" PYTHONPATH="${PYTHONPATH}" LC_ALL=C.UTF-8 ${legendary_bin} list-installed --show-dirs --tsv | grep "${GAME_NAME}" | tr -d '\n\r')"
  
  if [ "${LEGENDARY_LINE}" != "" ]; then
    EPIC_GAME_NAME="$(echo -n "${LEGENDARY_LINE}" | cut -f 1)"
    GAME_DIR="$(echo -n "${LEGENDARY_LINE}" | cut -f 7)"

    GAME_DIRNAME="$(basename "$(echo -n "${GAME_DIR}")")"

    HEROIC_BASEDIR="$(dirname "$(echo -n "${GAME_DIR}")")"
    PREFIX_BASEDIR="${HEROIC_BASEDIR}/WinePrefix"

    export DXVK_FRAME_RATE="0"
    #export DXVK_HUD="fps,scale=0.75"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH=${HOME}/.steam/steam
    export STEAM_COMPAT_DATA_PATH="${PREFIX_BASEDIR}/${GAME_DIRNAME}"
    export WINEDLLPATH="${PROTON_BASEDIR}/files/lib64/wine:${PROTON_BASEDIR}/files/lib/wine"

    if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
      mkdir -p "${STEAM_COMPAT_DATA_PATH}"
    fi

    if [[ "${legendary_bin}" =~ ^/(usr)/.* ]]; then
      legendary_bin="/run/host${legendary_bin}"
    else
      export PRESSURE_VESSEL_FILESYSTEMS_RO="${legendary_bin}"
    fi
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
    monitor_sh="$(which monitor.sh 2>/dev/null)"
    if [ -n "${monitor_sh}" ]; then
        ${monitor_sh} -p -b 0.1
    fi
    ${steamLinuxRuntime_bin} -- sh -c 'PYTHONHOME="$( dirname "$(echo -n "$( which python3 )" )" )" PYTHONPATH="$( python3 -c "import sys;print('\'':'\''.join(map(str, list(filter(None, sys.path)))))" )" '"${legendary_bin} launch \"${EPIC_GAME_NAME}\" ${language} --no-wine --wrapper \"'${PROTON_BASEDIR}/proton' waitforexitandrun\""
    if [ -n "${monitor_sh}" ]; then
      ${monitor_sh} on
    fi
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
