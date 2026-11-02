
# Cloud-Native GPU LLM Serving & Edge Inference Stack on K3s

A GitOps-driven, production-grade deployment of **vLLM / Ollama** and **Open WebUI** on Kubernetes (K3s), architected for both cloud compute instances (GCP L4/T4) and heterogeneous bare-metal edge environments with constrained system storage.

---

## Architecture Overview

```text
                           [ External Ingress ]
                                     │
                        NodePort 30000 / Bridge :3000
                                     ▼
                ┌─────────────────────────────────────────┐
                │        Open WebUI Pod / Frontend        │
                │        (Namespace: `ml-serving`)        │
                └────────────────────┬────────────────────┘
                                     │
           Internal K8s DNS: `http://vllm-service:8000/v1`
           or Container Gateway: `[http://host.docker.internal:11434](http://host.docker.internal:11434)`
                                     ▼
                ┌─────────────────────────────────────────┐
                │         Inference Engine Runtime        │
                │     (vLLM API Daemon / Ollama Core)     │
                └────────────┬────────────────────────────┘
                             │
       ┌─────────────────────┴─────────────────────┐
       ▼                                           ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│     NVIDIA Compute Engine     │   │   Decoupled Storage (PV/PVC)  │
│  Container Toolkit & Runtime  │   │  Dedicated Block Storage Path │
│   NVIDIA Device Plugin / CDI  │   │   (Image Layers, HF Weights)  │
└───────────────────────────────┘   └───────────────────────────────┘

```

### Core Architectural Decisions

* **Hardware Compute Offload:** Managed CUDA acceleration runtime utilizing NVIDIA GPUs (L4, T4, or Pascal-class bare-metal), executing full or partial parameter layer offload with active VRAM allocation tracking.
* **Storage Decoupling & Block Device Management:** Decoupled container runtime `data-root` and model weights storage from the OS root partition onto dedicated physical block devices (`/dev/sdb2` / secondary high-capacity volume), eliminating root volume exhaustion during large model pulls.
* **Service Mesh & Container Ingress:** Configured container-to-host bridge routing via `host.docker.internal` / K3s Service DNS and multi-interface API binding (`0.0.0.0`) to establish low-latency IPC across isolated network namespaces.
* **Stateful Ingestion with Retained PVCs:** Decoupled SQLite conversation histories, user vector embeddings, and web cache from the stateless UI container via persistent volume claims.

---

## Technical Specifications

| Parameter | Cloud VM Target | Edge / Bare-Metal Target |
| --- | --- | --- |
| **Host OS** | Ubuntu 22.04 LTS | Fedora / Enterprise Linux |
| **Orchestrator** | K3s (Lightweight Kubernetes) | K3s / Standalone OCI Runtime |
| **GPU Acceleration** | NVIDIA L4 / T4 | NVIDIA GeForce GTX 1050 Ti (4GB) |
| **Runtime Driver** | NVIDIA Container Toolkit + CDI | NVIDIA Driver 580.x + CUDA 13.0 |
| **Inference Daemon** | vLLM (OpenAI-compatible API) | Ollama Daemon (`0.0.0.0:11434`) |
| **Default Model** | `Qwen/Qwen2.5-Coder-1.5B-Instruct` | `qwen2.5-coder:1.5b` (Q4_K_M GGUF) |
| **Frontend UI** | Open WebUI (NodePort `30000`) | Open WebUI (`3000:8080`) |

---

## Infrastructure Provisioning & Bootstrapping

### 1. Storage & Daemon Decoupling (Pre-requisite for Storage-Constrained Nodes)

For nodes with constrained root partitions, relocate the container runtime storage directory to an external or secondary block storage volume:

```bash
# Provision runtime data directory on secondary block volume
sudo mkdir -p /run/media/kishan/DATA/docker-data

# Set data-root in container daemon configuration
sudo tee /etc/docker/daemon.json <<EOF "/run/media/kishan/DATA/docker-data" "data-root": ### & && -y 2. <your-repository-url Cluster Driver EOF Initialization K3s Node ``` ```bash apt-get cd clone docker git install restart sudo systemctl update { } ~> k8s-gpu-llm-serving
cd k8s-gpu-llm-serving

chmod +x scripts/*.sh
sudo ./scripts/01-install-gpu-drivers.sh
sudo reboot

```

After node initialization, bootstrap the K3s cluster with the NVIDIA container runtime:

```bash
sudo ./scripts/02-setup-k3s-gpu.sh

# Verify GPU device advertisement to Kubernetes
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu'

```

---

## Workload Deployment (Helm & GitOps)

Deploy the serving stack to the `ml-serving` namespace:

```bash
sudo kubectl create namespace ml-serving
sudo helm upgrade --install vllm-stack ./helm/vllm-stack \
  --namespace ml-serving \
  --wait --timeout 10m

# Verify pod status and rollout health
sudo kubectl -n ml-serving get pods,svc
sudo kubectl -n ml-serving rollout status deployment/vllm

```

---

## Verification & Observability

### 1. API Health & Inference Validation

```bash
# Query health endpoint
curl http://<NODE_IP>:30080/health

# Direct OpenAI-compatible completions request
curl http://<NODE_IP>:30080/v1/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen/Qwen2.5-Coder-1.5B-Instruct",
    "prompt": "Write a Kubernetes readiness probe in YAML:",
    "max_tokens": 128,
    "temperature": 0.2
  }' | jq

```

### 2. Hardware Resource Profiling

Inspect real-time GPU allocation, kernel driver memory occupancy, and compute processes:

```bash
# Check Kubernetes device allocation
kubectl describe node | grep -A3 -E '[nvidia.com/gpu](https://nvidia.com/gpu)|Allocated resources'

# Check low-level hardware memory usage
nvidia-smi

```

---

## Continuous Delivery (GitHub Actions)

Add the following repository secrets for automated deployment pipelines:

| Secret | Description |
| --- | --- |
| `GCP_INSTANCE_IP` | Target VM external IP or edge gateway IP |
| `GCP_VM_USER` | Remote SSH user |
| `GCP_SSH_PRIVATE_KEY` | Private SSH key mapped to authorized keys |

Every push to `main` executes Helm linting and continuous deployment via SSH to the cluster node.

---

## Cluster Operations & Lifecycle Management

```bash
# Stream inference logs
kubectl -n ml-serving logs deployment/vllm -f

# Hot-reload model weights or update parameters
helm upgrade vllm-stack ./helm/vllm-stack -n ml-serving \
  --reuse-values --set vllm.model=another/model

# Tear down workload (PVCs persist under default Retain policy)
helm uninstall vllm-stack -n ml-serving

```

```

---

### 2. Portfolio Project Card & Case Study Section

Use this structured entry directly in your personal portfolio's project section.

#### **Project Card (Overview)**
* **Title:** Cloud-Native GPU Inference & LLM Serving Infrastructure
* **Role:** DevOps & Cloud Engineer
* **Stack:** Kubernetes (K3s), Helm, NVIDIA Container Toolkit, Docker, vLLM / Ollama, Open WebUI, Linux, GitHub Actions
* **Short Description:** Architected a high-throughput, containerized LLM serving pipeline on Kubernetes and edge Linux nodes. Designed storage decoupling strategies across physical block devices, integrated NVIDIA GPU device offloading via CUDA/CDI, and automated GitOps deployments using Helm and GitHub Actions.

#### **Expanded Case Study / Modal View**
* **The Challenge:** Serving modern Large Language Models (LLMs) on constrained edge nodes or cloud VMs frequently leads to root partition exhaustion from heavy container layers and multi-gigabyte model weights. Additionally, bridging containerized web interfaces with hardware-bound inference runtimes requires non-trivial networking and GPU driver passthrough.
* **Key Implementations:**
  * **Storage Decoupling & Volume Architecture:** Separated volatile root OS partitions from persistent container workloads by re-routing runtime `data-root` paths to dedicated secondary block storage (`/dev/sdb2`), safeguarding host integrity.
  * **Hardware Compute Offload:** Configured NVIDIA Container Toolkit and K3s runtime integrations (`[nvidia.com/gpu](https://nvidia.com/gpu)` device plugin and CDI) to achieve deterministic GPU memory offloading for `Qwen2.5-Coder` workloads.
  * **Isolated Ingress & Inter-Service Networking:** Established secure cross-namespace and host-to-container service discovery via bridge gateway interfaces and Kubernetes Service DNS.
  * **CI/CD & GitOps Automation:** Developed GitHub Actions workflows to lint Helm charts, automate remote deployments, and maintain zero-downtime rollouts for LLM workloads.
* **Measurable Outcomes:** 
  * 0% root partition disk utilization impact during heavy model operations.
  * Sub-second time-to-first-token inference with active compute validation via `nvidia-smi`.
  * Fully repeatable Helm-based deployment reproducible across both bare-metal edge nodes and cloud compute instances.

```
