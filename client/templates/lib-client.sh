detect_router_platform() {
  if [ -f /etc/openwrt_release ] || [ -f /etc/openwrt_version ]; then
    echo "openwrt"
  elif [ -f /opt/etc/.entware_install_log ] || [ -d /opt/etc/ndm ]; then
    echo "keenetic"
  elif [ -f /etc/debian_version ]; then
    echo "linux"
  elif [ -d /etc/config ] && command -v uci >/dev/null 2>&1; then
    echo "openwrt"
  elif [ -f /opt/etc/init.d/rc.func ]; then
    echo "keenetic"
  elif [ -d /run/systemd/system ] || pidof systemd >/dev/null 2>&1; then
    echo "linux"
  else
    local uname_output=$(uname -a)
    if echo "$uname_output" | grep -qi "Keenetic\|Netcraze"; then
      echo "keenetic"
    elif echo "$uname_output" | grep -qi "OpenWrt\|LEDE\|ImmortalWrt"; then
      echo "openwrt"
    elif echo "$uname_output" | grep -qi "Linux"; then
      echo "linux"
    else
      echo "unknown"
    fi
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

detect_arch() {
  local arch=$(uname -m)
  case "$arch" in
    mips)
      if [ "$(echo -n I | hexdump -o 2>/dev/null | awk 'NR==1{print $2}')" = "000111" ]; then
        echo "mipsel"
      else
        echo "mips"
      fi
      ;;
    aarch64|arm64)
      echo "aarch64"
      ;;
    armv7l|armv6l)
      echo "armv7"
      ;;
    x86_64)
      echo "x86_64"
      ;;
    *)
      echo "unknown"
      ;;
  esac
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
