#!/usr/bin/env bash
set -euo pipefail

SWAPFILE="/swapfile"
SWAP_SIZE_MB=1024
SYSCTL_CONF="/etc/sysctl.d/99-bbr-fq.conf"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "ERROR: Please run as root."
    exit 1
  fi
}

mem_total_mb() {
  # MemTotal in kB
  awk '/MemTotal:/ {printf "%d\n", $2/1024}' /proc/meminfo
}

has_swap_active() {
  # /proc/swaps exists on Debian/Ubuntu; avoid relying on swapon output format
  awk 'NR>1 {print $1}' /proc/swaps | grep -qx "$SWAPFILE"
}

has_swap_in_fstab() {
  grep -qE "^[^#]*\s${SWAPFILE}\s" /etc/fstab 2>/dev/null
}

create_or_enable_swap_1g() {
  local mem_mb
  mem_mb="$(mem_total_mb)"

  echo "[INFO] Total RAM: ${mem_mb} MB"

  if (( mem_mb >= 1024 )); then
    echo "[OK] RAM >= 1GB, skip swap auto-create."
    return 0
  fi

  echo "[INFO] RAM < 1GB, ensure 1GB swap at ${SWAPFILE} ..."

  if has_swap_active; then
    echo "[OK] Swap already active: ${SWAPFILE}"
    return 0
  fi

  # If swapfile exists but not active, try to enable it
  if [[ -f "$SWAPFILE" ]]; then
    chmod 600 "$SWAPFILE" || true
    if swapon "$SWAPFILE" 2>/dev/null; then
      if ! has_swap_in_fstab; then
        echo "[INFO] Persisting swap in /etc/fstab"
        echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
      fi
      echo "[OK] Swap enabled."
      return 0
    fi
    echo "[WARN] ${SWAPFILE} exists but cannot be enabled. Recreating..."
    rm -f "$SWAPFILE"
  fi

  if [[ ! -f "$SWAPFILE" ]]; then
    echo "[INFO] Creating ${SWAP_SIZE_MB}MB swapfile..."
    fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE" 2>/dev/null || dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=progress
    chmod 600 "$SWAPFILE"
    mkswap "$SWAPFILE" >/dev/null
  fi

  swapon "$SWAPFILE"

  if ! has_swap_in_fstab; then
    echo "[INFO] Persisting swap in /etc/fstab"
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
  fi

  echo "[OK] Swap enabled."
}

enable_bbr_fq() {
  echo "[INFO] Enabling BBR + FQ..."

  # Try load module (may be built-in; failure is not fatal)
  modprobe tcp_bbr 2>/dev/null || true

  # Check availability (informational)
  local avail
  avail="$(sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null || true)"
  if [[ -n "$avail" ]] && ! grep -qw bbr <<<"$avail"; then
    echo "[WARN] 'bbr' not shown in available congestion control list:"
    echo "       ${avail}"
    echo "       Will still write sysctl; on some kernels/distros it may not take effect."
  fi

  cat > "$SYSCTL_CONF" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

  sysctl --system >/dev/null

  echo "[OK] Applied sysctl:"
  sysctl net.core.default_qdisc
  sysctl net.ipv4.tcp_congestion_control
}

show_summary() {
  echo
  echo "========== Summary =========="
  free -h || true
  echo
  echo "Swap:"
  swapon --show || true
  echo
  echo "BBR/FQ:"
  sysctl net.core.default_qdisc || true
  sysctl net.ipv4.tcp_congestion_control || true
  echo "============================="
}

main() {
  require_root
  create_or_enable_swap_1g
  enable_bbr_fq
  show_summary
}

main "$@"
