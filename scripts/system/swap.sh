#!/usr/bin/env bash
set -euo pipefail

# ===== Swap Manager Script =====
# Support: Debian / Ubuntu
# Author: ztao59673-sudo

SWAPFILE="/swapfile"

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "❌ Please run as root"
    exit 1
  fi
}

detect_swap() {
  swapon --show | grep -q "$SWAPFILE"
}

create_swap() {
  echo "Enter swap size (MB), e.g. 512 / 1024 / 2048:"
  read -rp "> " SIZE

  if ! [[ "$SIZE" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid number"
    exit 1
  fi

  echo "Creating ${SIZE}MB swap..."

  fallocate -l "${SIZE}M" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SIZE"
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
  swapon "$SWAPFILE"

  if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
  fi

  echo "✅ Swap created successfully"
}

delete_swap() {
  if detect_swap; then
    swapoff "$SWAPFILE"
  fi

  rm -f "$SWAPFILE"
  sed -i "\|$SWAPFILE|d" /etc/fstab

  echo "✅ Swap removed"
}

show_status() {
  echo "---- Memory ----"
  free -h
  echo
  echo "---- Swap ----"
  swapon --show || true
}

menu() {
  echo "============================"
  echo " Swap Management Script"
  echo "============================"
  echo "1) Show swap status"
  echo "2) Create swap"
  echo "3) Delete swap"
  echo "0) Exit"
  echo "============================"
  read -rp "Choose: " CHOICE

  case "$CHOICE" in
    1) show_status ;;
    2) create_swap ;;
    3) delete_swap ;;
    0) exit 0 ;;
    *) echo "❌ Invalid choice" ;;
  esac
}

require_root
menu
