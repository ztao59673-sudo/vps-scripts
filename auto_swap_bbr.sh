#!/usr/bin/env bash
set -euo pipefail

SWAPFILE="/swapfile"
SWAP_SIZE_MB=1024
SYSCTL_CONF="/etc/sysctl.d/99-bbr-fq.conf"
SSH_KEYS_URL="https://github.com/ztao59673-sudo.keys"
SSHD_DROPIN="/etc/ssh/sshd_config.d/99-codex-hardening.conf"

require_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "ERROR: Please run as root."
    exit 1
  fi
}

mem_total_mb() {
  awk '/MemTotal:/ {printf "%d\n", $2/1024}' /proc/meminfo
}

has_swap_active() {
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

  echo "[INFO] Creating ${SWAP_SIZE_MB}MB swapfile..."
  fallocate -l "${SWAP_SIZE_MB}M" "$SWAPFILE" 2>/dev/null || \
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="$SWAP_SIZE_MB" status=progress
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE" >/dev/null
  swapon "$SWAPFILE"

  if ! has_swap_in_fstab; then
    echo "[INFO] Persisting swap in /etc/fstab"
    echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
  fi

  echo "[OK] Swap enabled."
}

enable_bbr_fq() {
  echo "[INFO] Enabling BBR + FQ..."

  modprobe tcp_bbr 2>/dev/null || true

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

fetch_keys() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SSH_KEYS_URL"
    return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -qO- "$SSH_KEYS_URL"
    return 0
  fi
  echo "ERROR: Need curl or wget to fetch SSH keys."
  return 1
}

ensure_sshd_include() {
  local main_conf="/etc/ssh/sshd_config"
  if [[ -f "$main_conf" ]] && ! grep -qE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' "$main_conf"; then
    echo "" >> "$main_conf"
    echo "Include /etc/ssh/sshd_config.d/*.conf" >> "$main_conf"
  fi
}

configure_ssh_key_login() {
  echo "[INFO] Configuring SSH key-only login..."

  local keys
  keys="$(fetch_keys)"
  if [[ -z "$keys" ]]; then
    echo "ERROR: No SSH keys fetched from ${SSH_KEYS_URL}"
    exit 1
  fi

  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  printf "%s\n" "$keys" > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys

  mkdir -p /etc/ssh/sshd_config.d
  ensure_sshd_include

  cat > "$SSHD_DROPIN" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
UsePAM yes
EOF

  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files 2>/dev/null | grep -qE '^ssh\.socket'; then
      systemctl stop ssh.socket || true
      systemctl disable ssh.socket || true
    fi
    if systemctl list-unit-files 2>/dev/null | grep -qE '^ssh\.service'; then
      systemctl reload ssh || systemctl restart ssh
    elif systemctl list-unit-files 2>/dev/null | grep -qE '^sshd\.service'; then
      systemctl reload sshd || systemctl restart sshd
    fi
  else
    service ssh reload 2>/dev/null || service ssh restart 2>/dev/null || true
  fi

  echo "[OK] SSH key-only login enabled."
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
  configure_ssh_key_login
  show_summary
}

main "$@"
