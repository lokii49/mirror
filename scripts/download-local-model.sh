#!/usr/bin/env bash
set -euo pipefail

MODEL_URL="https://huggingface.co/bartowski/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"
DEST_DIR="${1:-mirror/LocalModels}"
DEST_FILE="${DEST_DIR}/Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"

mkdir -p "${DEST_DIR}"

echo "Downloading Qwen2.5 1.5B Instruct Q4_K_M..."
echo "Destination: ${DEST_FILE}"
curl -L --fail --continue-at - \
  "${MODEL_URL}" -o "${DEST_FILE}"
echo "Done."
