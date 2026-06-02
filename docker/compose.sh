#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
RESOLVER_SCRIPT="${SCRIPT_DIR}/scripts/resolve-docker-config.py"

assert_supported_host_os() {
    local os_name
    os_name="$(uname -s)"
    case "${os_name}" in
        Linux)
            ;;
        Darwin)
            echo "当前不支持 macOS 运行入口。请改用 Linux 或 Windows。" >&2
            exit 1
            ;;
        *)
            echo "当前仅支持 Linux 和 Windows 宿主机。检测到：${os_name}" >&2
            exit 1
            ;;
    esac
}

docker_runtime_supports_gpu() {
    local runtimes_json
    runtimes_json="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
    [[ "${runtimes_json}" == *'"nvidia"'* ]]
}

resolve_gpu_mode() {
    local raw_mode="${COMFYUI_GPU_MODE:-auto}"
    local normalized_mode="${raw_mode,,}"

    case "${normalized_mode}" in
        auto)
            if docker_runtime_supports_gpu; then
                GPU_ENABLED=1
            else
                GPU_ENABLED=0
            fi
            ;;
        on|true|1|yes)
            GPU_ENABLED=1
            ;;
        off|false|0|no)
            GPU_ENABLED=0
            ;;
        *)
            echo "不支持的 COMFYUI_GPU_MODE：${raw_mode}。可选值：auto、on、off。" >&2
            exit 1
            ;;
    esac

    GPU_MODE_RESOLVED="${normalized_mode}"
}

create_gpu_override_file() {
    GPU_OVERRIDE_FILE="$(mktemp "${TMPDIR:-/tmp}/comfyui-compose-gpu.XXXXXX.yml")"
    cat > "${GPU_OVERRIDE_FILE}" <<'EOF'
services:
  comfyui-runtime:
    gpus: all
  comfyui-devel:
    gpus: all
EOF
}

cleanup_gpu_override_file() {
    if [[ -n "${GPU_OVERRIDE_FILE:-}" && -f "${GPU_OVERRIDE_FILE}" ]]; then
        rm -f "${GPU_OVERRIDE_FILE}"
    fi
}

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
assert_supported_host_os
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
resolve_gpu_mode
trap cleanup_gpu_override_file EXIT

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
echo "[Compose] COMFYUI_GPU_MODE=${COMFYUI_GPU_MODE}"
echo "[Compose] GPU_ENABLED=${GPU_ENABLED}"
echo "[Compose] RUNTIME_IMAGE_TAG=${RUNTIME_IMAGE_TAG}"
echo "[Compose] DEVEL_IMAGE_TAG=${DEVEL_IMAGE_TAG}"

COMPOSE_ARGS=(compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}")
if [[ "${GPU_ENABLED}" -eq 1 ]]; then
    create_gpu_override_file
    COMPOSE_ARGS+=(-f "${GPU_OVERRIDE_FILE}")
fi
COMPOSE_ARGS+=("$@")

docker "${COMPOSE_ARGS[@]}"
