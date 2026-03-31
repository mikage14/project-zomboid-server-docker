#!/bin/bash
set -euo pipefail

TARGET_DIR="${STEAMAPPDIR}/java/zombie/popman"
mkdir -p "${TARGET_DIR}"

NMC_REF="${NMC_REF:-main}"
NMC_BASE_URL="${NMC_BASE_URL:-https://raw.githubusercontent.com/m0d1nst4ll3r/ProjectZomboid-Culling-Fix/${NMC_REF}}"
NMC_INSTALL_CLIENT_CLASS="${NMC_INSTALL_CLIENT_CLASS:-1}"

download_file() {
  local url="$1"
  local dest="$2"
  local tmp="${dest}.tmp"

  echo "*** INFO: Downloading $(basename "${dest}") from ${url}"
  curl -fsSL "${url}" -o "${tmp}"
  mv "${tmp}" "${dest}"
}

download_file "${NMC_BASE_URL}/NetworkZombiePacker.class" "${TARGET_DIR}/NetworkZombiePacker.class"

if [ "${NMC_INSTALL_CLIENT_CLASS}" == "1" ] || [ "${NMC_INSTALL_CLIENT_CLASS,,}" == "true" ]; then
  download_file "${NMC_BASE_URL}/ZombieCountOptimiser.class" "${TARGET_DIR}/ZombieCountOptimiser.class"
fi

chown -R "${USER}:${USER}" "${TARGET_DIR}" || true
echo "*** INFO: No Mo Culling patch applied to ${TARGET_DIR}"
