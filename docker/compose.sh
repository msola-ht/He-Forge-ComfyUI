#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
RESOLVER_SCRIPT="${SCRIPT_DIR}/scripts/resolve-docker-config.py"

ensure_env_file() {
    if [[ ! -f "${ENV_FILE}" && -f "${ENV_EXAMPLE_FILE}" ]]; then
        cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
    fi
}

resolve_python_command() {
    if command -v python >/dev/null 2>&1; then
        PYTHON_BIN="python"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        PYTHON_BIN="python3"
        return 0
    fi

    echo "未找到可用的 Python 解释器，请安装 python 或 python3。" >&2
    exit 1
}

ensure_env_file
resolve_python_command

if [[ $# -gt 0 && "$1" == "build" ]]; then
    echo "构建入口已统一为 docker/build.sh。请使用：bash docker/build.sh" >&2
    exit 1
fi

eval "$(
    "${PYTHON_BIN}" "${RESOLVER_SCRIPT}" \
        --mode compose \
        --env-file "${ENV_FILE}"
)"

export CUDA_VERSION="${CUDA_VERSION}"
export UBUNTU_CACHE_KEY="${UBUNTU_CACHE_KEY}"
export APT_CACHE_KEY="${APT_CACHE_KEY}"
export CONDA_CACHE_KEY="${CONDA_CACHE_KEY}"
export PIP_CACHE_KEY="${PIP_CACHE_KEY}"
export PYTORCH_INDEX_URL="${PYTORCH_INDEX_URL}"
export TORCHVISION_VERSION="${TORCHVISION_VERSION}"
export TORCHAUDIO_VERSION="${TORCHAUDIO_VERSION}"
export XFORMERS_VERSION="${XFORMERS_VERSION}"
export BUILDER_CUDA_IMAGE="${BUILDER_CUDA_IMAGE}"
export RUNTIME_CUDA_IMAGE="${RUNTIME_CUDA_IMAGE}"
export DEVEL_CUDA_IMAGE="${DEVEL_CUDA_IMAGE}"
export RUNTIME_IMAGE_TAG="${RUNTIME_IMAGE_TAG}"
export DEVEL_IMAGE_TAG="${DEVEL_IMAGE_TAG}"

echo "[Compose] CUDA_IMAGE_VERSION=${CUDA_IMAGE_VERSION}"
echo "[Compose] PYTORCH_CUDA_PROFILE=${PYTORCH_CUDA_PROFILE}"
echo "[Compose] UBUNTU_VERSION=${UBUNTU_VERSION}"
echo "[Compose] TORCH_VERSION=${TORCH_VERSION}"
echo "[Compose] RUNTIME_IMAGE_TAG=${RUNTIME_IMAGE_TAG}"
echo "[Compose] DEVEL_IMAGE_TAG=${DEVEL_IMAGE_TAG}"

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
