#!/bin/bash

declare -a STEAM_LIBRARY_FOLDERS

STEAM_ROOT="${HOME}/.steam/root"
STEAM_LIBRARY_FOLDERS=( "${STEAM_ROOT}/steamapps" )
STEAM_LIBRARY_FOLDER_FILE="${STEAM_ROOT}/steamapps/libraryfolders.vdf"
PROTON_CUSTOM_BASEDIR="${STEAM_ROOT}/compatibilitytools.d"

if [ -f "${STEAM_LIBRARY_FOLDER_FILE}" ]; then
  while read folder; do
    STEAM_LIBRARY_FOLDERS+=( "${folder}/steamapps" )
  done <<< "$(sed -ne "s/.*\"[[:digit:]]\+\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${STEAM_LIBRARY_FOLDER_FILE}")"
fi

legendary_bin="$(which legendary)"
if [ ! -f  "${legendary_bin}" ]; then
  echo "Legendary executable not found."
  exit
fi

export LC_ALL=en_US.UTF-8
export PRESSURE_VESSEL_FILESYSTEMS_RO="${legendary_bin}"

if [ $# -ge 1 ]; then
  GAME_NAME="$1"

  if [ $# -ge 2 ]; then
    PROTON_VER="$2"
  else
    PROTON_VER="Proton-6.14-GE-2"
  fi

  PROTON_ACF="$(grep -l "\"${PROTON_VER}\"" $( printf '%s/*.acf ' "${STEAM_LIBRARY_FOLDERS[@]}" ) )"
  if [ -f "${PROTON_ACF[@]}" ]; then
    PROTON_DIR="$( dirname "$(echo -n "${PROTON_ACF}")" )"
    PROTON_INSTALLDIR="$(sed -ne "s/.*\"installdir\"[[:space:]]\+\"\\([^\"\]\+\)\".*/\1/p" "${PROTON_ACF}")"
    PROTON_BASEDIR="${PROTON_DIR}/common/${PROTON_INSTALLDIR}"
  else   
    PROTON_CUSTOM_VDF="$(grep -l "\"${PROTON_VER}\"" ${PROTON_CUSTOM_BASEDIR}/*/compatibilitytool.vdf)"
    if [ -f "${PROTON_CUSTOM_VDF}" ]; then
      PROTON_BASEDIR="$( dirname "$(echo -n "${PROTON_CUSTOM_VDF}")" )"
    fi
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

  LEGENDARY_LINE="$(${legendary_bin} list-installed --show-dirs --tsv | grep "${GAME_NAME}" | tr -d '\n\r')"
  
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
    export PYTHONHOME=/usr
    export PYTHONPATH=/usr/lib64/python3.8/lib-dynload:/usr/lib64/python3.8
    export WINEDLLPATH="${PROTON_BASEDIR}/files/lib64/wine:${PROTON_BASEDIR}/files/lib/wine"

    if [ ! -d "${STEAM_COMPAT_DATA_PATH}" ]; then
      mkdir -p "${STEAM_COMPAT_DATA_PATH}"
    fi

    ${steamLinuxRuntime_bin} -- ${legendary_bin} launch "${EPIC_GAME_NAME}" --language it --no-wine --wrapper "'${PROTON_BASEDIR}/proton' waitforexitandrun"
  fi
fi
