#!/usr/bin/env bash
set -euo pipefail

# =========================
# VPS Scripts One-Click Menu
# Repo: ztao59673-sudo/vps-scripts
# Run:  bash <(curl -fsSL https://raw.githubusercontent.com/ztao59673-sudo/vps-scripts/main/install.sh)
# =========================

REPO_OWNER="ztao59673-sudo"
REPO_NAME="vps-scripts"

# 允许你通过环境变量指定分支/标签/commit
# 例如：BRANCH=v1.0 bash <(curl -fsSL .../install.sh)
BRANCH="${BRANCH:-main}"

RAW_BASE="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"

need_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_downloader() {
  if need_cmd curl; then
    return 0
  fi
  if need_cmd wget; then
    return 0
  fi

  echo "[-] curl/wget not found, trying to install curl..."

  if need_cmd apt; then
    apt update -y
    apt install -y curl
  elif need_cmd yum; then
    yum install -y curl
  elif need_cmd dnf; then
    dnf install -y curl
  elif need_cmd apk; then
    apk add --no-cache curl
  else
    echo "[!] Cannot install curl automatically. Please install curl or wget."
    exit 1
  fi
}

fetch_to() {
  local url="$1" out="$2"
  if need_cmd curl; then
    curl -fsSL "$url" -o "$out"
  else
    wget -qO "$out" "$url"
  fi
}

run_remote_script() {
  local relpath="$1"
  local url="${RAW_BASE}/${relpath}"
  local tmp
  tmp="$(mktemp -t vps-scripts.XXXXXX.sh)"

  echo
  echo "[+] Fetch: ${url}"
  if ! fetch_to "$url" "$tmp"; then
    echo "[!] Failed to download: ${url}"
    rm -f "$tmp"
    exit 1
  fi

  chmod +x "$tmp"
  bash "$tmp"
  rm -f "$tmp"
}

require_root_for() {
  # 有些脚本需要 root（swap/bbr/ssh等），这里统一要求 root 执行
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "[!] This action requires root. Please run as root:"
    echo "    sudo -i   (or)   sudo bash <(curl -fsSL .../install.sh)"
    exit 1
  fi
}

show_banner() {
  echo "=========================================="
  echo " VPS Scripts - One-Click Installer (curl)"
  echo " Repo   : ${REPO_OWNER}/${REPO_NAME}"
  echo " Branch : ${BRANCH}"
  echo "=========================================="
}

main_menu() {
  while true; do
    show_banner
    echo "1) Swap 管理 (scripts/system/swap.sh)"
    echo "2) (预留) BBR/FQ (scripts/system/bbr.sh)"
    echo "3) (预留) SSH 加固 (scripts/system/ssh_harden.sh)"
    echo "4) (预留) Sing-box 安装 (scripts/proxy/singbox_install.sh)"
    echo "------------------------------------------"
    echo "9) 测试：仅下载并显示脚本头部(不执行)"
    echo "0) Exit"
    echo
    read -rp "Choose: " choice

    case "$choice" in
      1)
        require_root_for
        run_remote_script "scripts/system/swap.sh"
        ;;
      2)
        require_root_for
        run_remote_script "scripts/system/bbr.sh"
        ;;
      3)
        require_root_for
        run_remote_script "scripts/system/ssh_harden.sh"
        ;;
      4)
        require_root_for
        run_remote_script "scripts/proxy/singbox_install.sh"
        ;;
      9)
        ensure_downloader
        url="${RAW_BASE}/scripts/system/swap.sh"
        echo
        echo "[+] Fetch (no run): ${url}"
        if need_cmd curl; then
          curl -fsSL "$url" | head -n 30
        else
          wget -qO- "$url" | head -n 30
        fi
        echo
        read -rp "Press Enter to continue..." _
        ;;
      0) exit 0 ;;
      *) echo "[!] Invalid choice"; sleep 1 ;;
    esac

    echo
    read -rp "Press Enter to return to menu..." _
  done
}

ensure_downloader
main_menu
