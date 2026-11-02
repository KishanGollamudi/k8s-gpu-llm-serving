# GPU LLM Serving Stack on K3s

A GitOps-ready, production-oriented deployment of **vLLM** and **Open WebUI** on a lightweight Kubernetes cluster running on an NVIDIA GPU virtual machine.

## Architecture

```text
Browser
  │  NodePort 30000
  ▼
Open WebUI Service/Pod
  │  http://vllm-service:8000/v1 (Kubernetes DNS)
  ▼
 vLLM OpenAI-compatible API
  │  NVIDIA runtime + Device Plugin
  ▼
 NVIDIA L4 or T4 GPU
```

* NVIDIA userspace libraries and the kernel driver are installed on Ubuntu 22.04.
* The NVIDIA Container Toolkit configures containerd; K3s launches GPU containers through its NVIDIA runtime.
* The NVIDIA Kubernetes Device Plugin runs as a DaemonSet and advertises `nvidia.com/gpu` resources. Kubernetes injects the compatible NVIDIA runtime and GPU device into the pod; modern container runtimes may use CDI, while the scheduling contract remains `nvidia.com/gpu`.
* vLLM serves `Qwen/Qwen2.5-Coder-1.5B-Instruct` on port 8000.
* Open WebUI connects internally to the in-cluster vLLM service and exposes port 8080 externally on NodePort 30000.

## GCP VM requirements

* Ubuntu 22.04 LTS
* GCP Compute Engine GPU type L4 or T4
* GPU-capable machine type with GPU mode and serial port access enabled as needed
* OS disk of at least 50 GB and sufficient boot disk throughput
* Firewall rules for ports `30000` and `30080`, or preferably a restricted load balancer/VPN path
* An SSH key available to the VM and GitHub Actions

## Bootstrap the host

```bash
sudo apt-get update
sudo apt-get install -y git
cd ~
git clone <your-repository-url> k8s-gpu-llm-serving
cd k8s-gpu-llm-serving

chmod +x scripts/*.sh
sudo ./scripts/01-install-gpu-drivers.sh
sudo reboot
```

After reboot, verify and complete the K3s/GPU setup:

```bash
sudo ./scripts/02-setup-k3s-gpu.sh
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu'
```

The setup script installs Helm, disables swap, configures containerd and the NVIDIA runtime, starts K3s without Traefik, and installs the NVIDIA Device Plugin.

## Deploy the Helm chart

```bash
sudo kubectl create namespace ml-serving
sudo helm upgrade --install vllm-stack ./helm/vllm-stack \
  --namespace ml-serving \
  --wait --timeout 10m

sudo kubectl -n ml-serving get pods,svc
sudo kubectl -n ml-serving rollout status deployment/vllm
sudo kubectl -n ml-serving logs deployment/vllm -f
```

The first deployment downloads the Hugging Face model and can take longer than the Kubernetes pod startup grace period on a cold disk.

## Test the API

Use the VM's external IP, only while the firewall permits the selected port:

```bash
curl http://<VM_EXTERNAL_IP>:30080/health
./scripts/test-inference.sh <VM_EXTERNAL_IP> 30080
```

Direct OpenAI-compatible completions request:

```bash
curl http://<VM_EXTERNAL_IP>:30080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"Qwen/Qwen2.5-Coder-1.5B-Instruct",
    "prompt":"Write a Kubernetes probe in YAML:",
    "max_tokens":128,
    "temperature":0.2
  }' | jq
```

Open WebUI at `http://<VM_EXTERNAL_IP>:30000`. Create the first administrator account when prompted. Open WebUI uses `http://vllm-service:8000/v1` through K3s DNS for all inference traffic.

## GitHub Actions deployment

Add these repository secrets:

| Secret | Value |
|---|---|
| `GCP_INSTANCE_IP` | VM external IP |
| `GCP_VM_USER` | Linux SSH user |
| `GCP_SSH_PRIVATE_KEY` | Private SSH key corresponding to the VM's authorized key |

Every push to `main` lints the chart and SSH-deploys it on the VM. Configure the repository checkout path on the VM as `~/k8s-gpu-llm-serving` before the first workflow run. Pushes require Git authentication for the VM if the repository is private.

## Operations

```bash
# Inspect GPU allocation and pod placement
kubectl describe node | grep -A3 -E 'nvidia.com/gpu|Allocated resources'

# Tail inference logs
kubectl -n ml-serving logs deployment/vllm -f

# Change image/model settings
helm upgrade vllm-stack ./helm/vllm-stack -n ml-serving \
  --reuse-values --set vllm.model=another/model

# Remove the stack (PVCs are retained with policy Retain unless the storage provider defaults otherwise)
helm uninstall vllm-stack -n ml-serving
```

For internet-facing deployments, place Open WebUI behind HTTPS, restrict firewall ingress to trusted networks, enable authentication and audit logging, pin image/model versions, and add a secret-backed model registry or persistent cache rather than relying on mutable tags.
