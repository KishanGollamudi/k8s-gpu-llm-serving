#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run this script with sudo or as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ubuntu-drivers-common build-essential linux-headers-"$(uname -r)" dkms

ubuntu-drivers install

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "Installation complete. NVIDIA driver information:"
  nvidia-smi || true
fi

echo
echo "A reboot is required for the NVIDIA kernel modules to load."
read -r -p "Reboot now? [y/N] " reboot_answer
if [[ "${reboot_answer,,}" == "y" || "${reboot_answer,,}" == "yes" ]]; then
  reboot
fi
