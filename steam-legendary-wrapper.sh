#!/bin/bash

# /home/alex/.local/share/Steam/steamapps/libraryfolders.vdf
# /mnt/data/steam-library/steamapps/appmanifest_1391110.acf

steamLinuxRuntime_bin="/mnt/data/steam-library/steamapps/common/SteamLinuxRuntime_soldier/run"
legendary_bin="$(which legendary)"

export LC_ALL=en_US.UTF-8
export PRESSURE_VESSEL_FILESYSTEMS_RO="${legendary_bin}"

if [ $# -ge 1 ]; then
  GAME_NAME="$1"

  if [ $# -ge 2 ]; then
    PROTON_VER="$2"
  else
    PROTON_VER="Proton-6.14-GE-2"
  fi

  LEGENDARY_LINE="$(${legendary_bin} list-installed --show-dirs --tsv | grep "${GAME_NAME}" | tr -d '\n\r')"
  
  if [ "${LEGENDARY_LINE}" != "" ]; then
    EPIC_GAME_NAME="$(echo -n "${LEGENDARY_LINE}" | cut -f 1)"
    GAME_DIR="$(echo -n "${LEGENDARY_LINE}" | cut -f 7)"

    GAME_DIRNAME="$(basename "$(echo -n "${GAME_DIR}")")"

    HEROIC_BASEDIR="$(dirname "$(echo -n "${GAME_DIR}")")"
    PREFIX_BASEDIR="${HEROIC_BASEDIR}/WinePrefix"
    PROTON_BASEDIR="${HOME}/.steam/root/compatibilitytools.d/${PROTON_VER}"

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
