#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Please run this script with sudo or as root." >&2
  exit 1
fi

if ! command -v nvidia-smi >/dev/null 2>&1 || ! nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi is unavailable or the NVIDIA driver is not functioning." >&2
  exit 1
fi

# Prevent Kubernetes from treating GPU memory or disks as swap-backed resources.
swapoff -a
sed -ri '/\s+swap\s+/ s/^#?/#/' /etc/fstab

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl jq ca-certificates

# Install the NVIDIA Container Toolkit using NVIDIA's packaged repository.
export NVIDIA_CONTAINER_TOOLKIT_URL="https://nvidia.github.io/libnvidia-container/gpgkey"
mkdir -p /usr/share/keyrings
curl -fsSL "${NVIDIA_CONTAINER_TOOLKIT_URL}" | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update
apt-get install -y nvidia-container-toolkit

nvidia-ctk runtime configure --runtime=containerd
systemctl restart containerd || true

# The NVIDIA runtime is registered as K3s' default runtime for GPU workloads.
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--default-runtime=nvidia --disable=traefik" sh -

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p "${SUDO_USER:+/home/${SUDO_USER}}"

if [[ -n "${SUDO_USER:-}" ]]; then
  install -d -m 700 -o "${SUDO_USER}" -g "$(id -gn "${SUDO_USER}")" "/home/${SUDO_USER}/.kube"
  install -m 600 -o "${SUDO_USER}" -g "$(id -gn "${SUDO_USER}")" /etc/rancher/k3s/k3s.yaml "/home/${SUDO_USER}/.kube/config"
  sed -i "s#127.0.0.1#$(hostname -I | awk '{print $1}')#g" "/home/${SUDO_USER}/.kube/config"
fi

# Install Helm through its official packaged repository.
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

kubectl wait --for=condition=Ready node --all --timeout=180s
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml
kubectl -n kube-system rollout status daemonset/nvidia-device-plugin-daemonset --timeout=180s

# Check for GPU advertisinement through the extended Kubernetes resource API.
if ! kubectl get nodes -o json | jq -e '.items[].status.capacity["nvidia.com/gpu"] | tonumber > 0' >/dev/null; then
  echo "Kubernetes does not yet advertise nvidia.com/gpu capacity." >&2
  kubectl get nodes -o yaml
  exit 1
fi

echo "GPU capacity successfully registered:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.capacity.nvidia\.com/gpu}{"\n"}{end}'
