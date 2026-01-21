#!/usr/bin/env bash
set -euo pipefail

# ===== BBR Enable Script =====
# Support: Debian / Ubuntu
# Author: ztao59673-sudo

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "❌ Please run as root"
    exit 1
  fi
}

kernel_check() {
  local ver
  ver="$(uname -r | cut -d. -f1)"
  if (( ver < 4 )); then
    echo "❌ Kernel too old (<4.x), cannot enable BBR"
    exit 1
  fi
}

show_status() {
  echo "---- Kernel ----"
  uname -r
  echo
  echo "---- TCP congestion control ----"
  sysctl net.ipv4.tcp_congestion_control
  echo
  echo "---- Default qdisc ----"
  sysctl net.core.default_qdisc
  echo
  echo "---- BBR loaded ----"
  lsmod | grep -q bbr && echo "bbr module loaded" || echo "bbr module not loaded"
}

enable_bbr() {
  echo "Enabling BBR..."

  modprobe tcp_bbr || true

  cat >/etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

  sysctl --system >/dev/null

  echo "✅ BBR enabled"
}

disable_bbr() {
  echo "Disabling BBR (restore cubic)..."

  cat >/etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc = pfifo_fast
net.ipv4.tcp_congestion_control = cubic
EOF

  sysctl --system >/dev/null

  echo "✅ BBR disabled (restored cubic)"
}

menu() {
  while true; do
    echo "============================"
    echo " BBR Management Script"
    echo "============================"
    echo "1) Show status"
    echo "2) Enable BBR"
    echo "3) Disable BBR (restore cubic)"
    echo "0) Exit"
    echo "============================"
    read -rp "Choose: " n

    case "$n" in
      1) show_status ;;
      2) kernel_check; enable_bbr ;;
      3) disable_bbr ;;
      0) exit 0 ;;
      *) echo "❌ Invalid choice" ;;
    esac

    echo
    read -rp "Press Enter to continue..." _
  done
}

require_root
menu
