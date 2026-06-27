detect_router_platform() {
  if command -v ndmc >/dev/null 2>&1 || [ -d /opt/etc/ndm ]; then
    echo "keenetic"
    return
  fi

  if [ -f /etc/openwrt_release ] || [ -f /etc/openwrt_version ] || \
     { [ -d /etc/config ] && command -v uci >/dev/null 2>&1; }; then
    echo "openwrt"
    return
  fi

  case "$(uname -a)" in
    *Keenetic*|*Netcraze*|*NDMS*)   echo "keenetic"; return ;;
    *OpenWrt*|*LEDE*|*ImmortalWrt*) echo "openwrt"; return ;;
  esac

  if [ -f /etc/debian_version ] || [ -f /etc/os-release ] || \
     [ -d /run/systemd/system ] || pidof systemd >/dev/null 2>&1; then
    echo "linux"
    return
  fi

  if [ "$(uname -s)" = "Linux" ]; then
    echo "linux"
  else
    echo "unknown"
  fi
}

detect_phobos_dir() {
  local platform="$1"

  if [ "$platform" = "keenetic" ]; then
    echo "/opt/etc/Phobos"
  elif [ "$platform" = "openwrt" ]; then
    echo "/etc/Phobos"
  elif [ "$platform" = "linux" ]; then
    echo "/opt/Phobos"
  else
    if [ -d "/opt" ] && [ -d "/opt/etc" ]; then
      echo "/opt/etc/Phobos"
    else
      echo "/etc/Phobos"
    fi
  fi
}

normalize_arch() {
  case "$1" in
    x86_64*|x64*|amd64*)                       echo "x86_64" ;;
    aarch64*|arm64*)                           echo "aarch64" ;;
    armv7*|armv6*|armhf*|armel*|arm_*|arm-*|arm) echo "armv7" ;;
    mipsel*|mips64el*)                          echo "mipsel" ;;
    mips*)                                      echo "mips" ;;
    *)                                          echo "unknown" ;;
  esac
}

detect_arch_endianness() {
  local base="$1"
  local word=$(printf '\1\0' | od -x 2>/dev/null | head -1 | awk '{print $2}')
  if [ "$word" = "0001" ]; then
    echo "${base}el"
  else
    echo "$base"
  fi
}

detect_arch() {
  local raw=""

  if [ -r /opt/etc/entware_release ]; then
    raw=$(grep '^arch=' /opt/etc/entware_release 2>/dev/null | head -1 | cut -d= -f2)
  fi

  if [ -z "$raw" ] && [ -r /etc/openwrt_release ]; then
    raw=$( . /etc/openwrt_release 2>/dev/null; echo "$DISTRIB_ARCH" )
  fi

  if [ -z "$raw" ] && command -v opkg >/dev/null 2>&1; then
    raw=$(opkg print-architecture 2>/dev/null | grep '^arch ' | grep -v ' all ' | grep -v ' noarch ' | sort -k3 -n | tail -1 | awk '{print $2}')
  fi

  if [ -z "$raw" ] && command -v apk >/dev/null 2>&1; then
    raw=$(apk --print-arch 2>/dev/null)
  fi

  if [ -z "$raw" ]; then
    raw=$(uname -m)
    case "$raw" in
      mips|mips64) raw=$(detect_arch_endianness "$raw") ;;
    esac
  fi

  normalize_arch "$raw"
}

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт требует root привилегии. Запустите: su -c '$0'"
    exit 1
  fi
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

msg() { printf '%s\n' "$*"; }

print_status() {
  local status="$1"
  local message="$2"

  if [ "${status}" = "OK" ]; then
    printf "\\033[0;32m✓\\033[0m %s\n" "${message}"
  elif [ "${status}" = "WARN" ]; then
    printf "\\033[1;33m⚠\\033[0m %s\n" "${message}"
  else
    printf "\\033[0;31m✗\\033[0m %s\n" "${message}"
  fi
}

PKG_MGR=""
PKG_UPDATE=""
PKG_INSTALL=""

detect_pkg_manager() {
  if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_UPDATE="apk update"
    PKG_INSTALL="apk add"
  elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_UPDATE="opkg update"
    PKG_INSTALL="opkg install"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MGR="apt"
    PKG_UPDATE="apt-get update"
    PKG_INSTALL="apt-get install -y"
  else
    PKG_MGR=""
  fi
}

pkg_update() {
  [ -n "$PKG_MGR" ] || return 1
  $PKG_UPDATE
}

pkg_install() {
  [ -n "$PKG_MGR" ] || return 1
  $PKG_INSTALL "$@"
}

compute_slot_names() {
  local slot="$1"
  local suffix=""
  [ "$slot" -gt 0 ] && suffix="$slot"

  OBF_BINARY_NAME="wg-obfuscator${suffix}"
  OBF_CONF_NAME="wg-obfuscator${suffix}.conf"
  OBF_INIT_NAME="S$((49 + slot))wg-obfuscator"
  OBF_SERVICE_NAME="phobos-obfuscator${suffix}"

  if [ "$ROUTER_PLATFORM" = "openwrt" ]; then
    OBF_WG_IFACE="phobos_wg${suffix}"
  else
    OBF_WG_IFACE="phobos${suffix}"
  fi
}

registry_line_for_client() {
  [ -f "${PHOBOS_DIR}/registry" ] || return 0
  grep "^$1|" "${PHOBOS_DIR}/registry" 2>/dev/null | head -1
}

registry_field() {
  echo "$1" | cut -d'|' -f"$2"
}

registry_clients() {
  [ -f "${PHOBOS_DIR}/registry" ] || return 0
  cut -d'|' -f1 "${PHOBOS_DIR}/registry" 2>/dev/null | grep -v '^$'
}

registry_alloc_slot() {
  local max=-1 slot
  if [ -f "${PHOBOS_DIR}/registry" ]; then
    for slot in $(cut -d'|' -f2 "${PHOBOS_DIR}/registry" 2>/dev/null); do
      if [ "$slot" -gt "$max" ] 2>/dev/null; then
        max="$slot"
      fi
    done
  fi
  echo $((max + 1))
}

registry_alloc_port() {
  local base="${1:-13255}"
  local used=" "
  if [ -f "${PHOBOS_DIR}/registry" ]; then
    used=" $(cut -d'|' -f3 "${PHOBOS_DIR}/registry" 2>/dev/null | tr '\n' ' ')"
  fi
  local port="$base"
  while echo "$used" | grep -q " ${port} "; do
    port=$((port + 1))
  done
  echo "$port"
}

registry_add() {
  printf '%s\n' "$1" >> "${PHOBOS_DIR}/registry"
}

registry_remove_client() {
  local file="${PHOBOS_DIR}/registry"
  [ -f "$file" ] || return 0
  grep -v "^$1|" "$file" > "${file}.tmp" 2>/dev/null || true
  mv "${file}.tmp" "$file"
}
