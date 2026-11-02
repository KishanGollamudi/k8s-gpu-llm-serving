#!/usr/bin/env bash
set -euo pipefail

HOST="${1:-localhost}"
PORT="${2:-30080}"
BASE_URL="http://${HOST}:${PORT}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-900}"

command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

attempts=$((TIMEOUT_SECONDS / 5))
for ((i = 1; i <= attempts; i++)); do
  if curl --fail --silent --show-error "${BASE_URL}/health" >/dev/null; then
    echo "vLLM is healthy at ${BASE_URL}"
    break
  fi
  echo "Waiting for model weights to load (${i}/${attempts})..."
  sleep 5
  if (( i == attempts )); then
    echo "Timed out waiting for vLLM health." >&2
    exit 1
  fi
done

curl --fail --silent --show-error \
  -H 'Content-Type: application/json' \
  "${BASE_URL}/v1/completions" \
  -d '{
    "model":"Qwen/Qwen2.5-Coder-1.5B-Instruct",
    "prompt":"Write a Python function that returns the factorial of a non-negative integer.",
    "max_tokens":128,
    "temperature":0.2
  }' | jq
