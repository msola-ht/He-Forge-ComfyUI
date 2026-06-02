#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
ENV_EXAMPLE_FILE="${SCRIPT_DIR}/.env.example"
DOCKERFILE_PATH="docker/Dockerfile"
PLUGIN_MANIFEST_FILE="${SCRIPT_DIR}/plugins/custom-nodes.json"
RESOLVER_SCRIPT="${SCRIPT_DIR}/scripts/resolve-docker-config.py"
TEST_SCRIPT="${SCRIPT_DIR}/scripts/test.sh"

VARIANT="runtime"
BUILD_STAGE="final"
IMAGE_NAME=""
CUDA_IMAGE_VERSION=""
PYTORCH_CUDA_PROFILE=""
UBUNTU_VERSION=""
MINIFORGE_INSTALLER_URL=""
PYTHON_VERSION=""
COMFYUI_REPO=""
COMFYUI_REF=""
COMFYUI_RESOLVED_COMMIT=""
NODEJS_VERSION=""
TORCH_VERSION=""
PIP_INDEX_URL=""
PIP_EXTRA_INDEX_URL=""
PIP_TRUSTED_HOST=""
PYTORCH_INDEX_URL_OVERRIDE=""
PUSH=0
NO_CACHE=0
TEST_AFTER_BUILD=0

assert_supported_host_os() {
    local os_name
    os_name="$(uname -s)"
    case "${os_name}" in
        Linux)
            ;;
        Darwin)
            echo "当前不支持 macOS 构建。请改用 Linux 或 Windows。" >&2
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

needs_host_gateway_alias() {
    local value
    for value in "${PIP_INDEX_URL}" "${PIP_EXTRA_INDEX_URL}" "${PYTORCH_INDEX_URL_OVERRIDE:-}"; do
        if [[ "${value}" == *"host.docker.internal"* ]]; then
            return 0
        fi
    done
    return 1
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

usage() {
    cat <<'EOF'
用法：
  bash docker/build.sh [选项]

选项：
  --variant <runtime|devel>
  --build-stage <bootstrap|final>
  --image-name <name>
  --cuda-image-version <version>
  --pytorch-cuda-profile <profile>
  --ubuntu-version <version>
  --miniforge-installer-url <url>
  --python-version <prefix>
  --comfyui-repo <url>
  --comfyui-ref <ref>
  --nodejs-version <22|24>
  --torch-version <version>
  --pip-index-url <url>
  --pip-extra-index-url <url>
  --pip-trusted-host <host>
  --pytorch-index-url-override <url>
  --push
  --no-cache
  --test-after-build
  --from-env
  --help
EOF
}

ensure_env_file() {
    if [[ ! -f "${ENV_FILE}" && -f "${ENV_EXAMPLE_FILE}" ]]; then
        cp "${ENV_EXAMPLE_FILE}" "${ENV_FILE}"
    fi
}

has_buildkit_cache() {
    local path="$1"
    [[ -f "${path}/index.json" && -d "${path}/blobs" ]]
}

append_unique() {
    local value="$1"
    local item
    for item in "${CACHE_FROM_DIRS[@]:-}"; do
        if [[ "${item}" == "${value}" ]]; then
            return 0
        fi
    done
    CACHE_FROM_DIRS+=("${value}")
}

remove_sibling_caches() {
    local parent_dir="$1"
    local current_dir="$2"
    shift 2
    local patterns=("$@")
    local dir pattern matched

    [[ -d "${parent_dir}" ]] || return 0
    shopt -s nullglob
    for dir in "${parent_dir}"/*; do
        [[ -d "${dir}" ]] || continue
        [[ "${dir}" == "${current_dir}" ]] && continue
        [[ "${dir}" == *-new ]] && continue
        [[ "${dir}" == *-previous ]] && continue

        matched=0
        for pattern in "${patterns[@]}"; do
            if [[ "$(basename "${dir}")" == ${pattern} ]]; then
                matched=1
                break
            fi
        done

        if [[ "${matched}" -eq 1 ]]; then
            rm -rf "${dir}"
        fi
    done
    shopt -u nullglob
}

acquire_buildkit_cache_lock() {
    local lock_dir="$1"
    local timeout_seconds="${2:-600}"
    local start_time
    local now
    local last_modified
    local lock_age

    start_time="$(date +%s)"
    while ! mkdir "${lock_dir}" 2>/dev/null; do
        now="$(date +%s)"
        if [[ -d "${lock_dir}" ]]; then
            if last_modified="$(stat -f '%m' "${lock_dir}" 2>/dev/null)"; then
                :
            elif last_modified="$(stat -c '%Y' "${lock_dir}" 2>/dev/null)"; then
                :
            else
                last_modified=0
            fi

            lock_age=$((now - last_modified))
            if (( last_modified > 0 && lock_age >= timeout_seconds )); then
                echo "[BuildCache] remove stale rotate lock ${lock_dir}" >&2
                rmdir "${lock_dir}" 2>/dev/null || true
                continue
            fi
        fi

        if (( now - start_time >= timeout_seconds )); then
            echo "[BuildCache] 获取缓存轮换锁超时：${lock_dir}" >&2
            return 1
        fi
        sleep 1
    done
}

release_buildkit_cache_lock() {
    local lock_dir="$1"

    [[ -d "${lock_dir}" ]] || return 0
    rmdir "${lock_dir}"
}

remove_stale_new_dirs() {
    local parent_dir="$1"
    local exclude_path="$2"
    local min_age_seconds="${3:-86400}"
    local now
    local dir
    local last_modified
    local dir_age

    [[ -d "${parent_dir}" ]] || return 0
    now="$(date +%s)"
    shopt -s nullglob
    for dir in "${parent_dir}"/*-new; do
        [[ -d "${dir}" ]] || continue
        if [[ -n "${exclude_path}" && "${dir}" == "${exclude_path}" ]]; then
            continue
        fi
        if last_modified="$(stat -f '%m' "${dir}" 2>/dev/null)"; then
            :
        elif last_modified="$(stat -c '%Y' "${dir}" 2>/dev/null)"; then
            :
        else
            echo "[BuildCache] 无法读取目录修改时间，跳过清理：${dir}" >&2
            continue
        fi
        dir_age=$((now - last_modified))
        if (( dir_age < min_age_seconds )); then
            continue
        fi
        rm -rf "${dir}"
    done
    shopt -u nullglob
}

promote_buildkit_cache() {
    local current_dir="$1"
    local new_dir="$2"
    local backup_dir="${current_dir}-previous"

    if [[ ! -d "${new_dir}" ]] || ! has_buildkit_cache "${new_dir}"; then
        echo "[BuildCache] 新缓存目录不可用，保留现有缓存：${new_dir}" >&2
        return 1
    fi

    if [[ -e "${current_dir}" && -e "${backup_dir}" ]]; then
        echo "[BuildCache] remove stale backup ${backup_dir}"
        rm -rf "${backup_dir}"
    fi

    if [[ -e "${current_dir}" ]]; then
        echo "[BuildCache] backup current cache ${current_dir} -> ${backup_dir}"
        mv "${current_dir}" "${backup_dir}"
    fi

    if mv "${new_dir}" "${current_dir}"; then
        if [[ -e "${backup_dir}" ]]; then
            echo "[BuildCache] remove old cache backup ${backup_dir}"
            rm -rf "${backup_dir}"
        fi
        return 0
    fi

    if [[ -e "${backup_dir}" && ! -e "${current_dir}" ]]; then
        echo "[BuildCache] restore cache backup ${backup_dir} -> ${current_dir}" >&2
        mv "${backup_dir}" "${current_dir}"
    fi

    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --build-stage) BUILD_STAGE="$2"; shift 2 ;;
        --image-name) IMAGE_NAME="$2"; shift 2 ;;
        --cuda-image-version) CUDA_IMAGE_VERSION="$2"; shift 2 ;;
        --pytorch-cuda-profile) PYTORCH_CUDA_PROFILE="$2"; shift 2 ;;
        --ubuntu-version) UBUNTU_VERSION="$2"; shift 2 ;;
        --miniforge-installer-url) MINIFORGE_INSTALLER_URL="$2"; shift 2 ;;
        --python-version) PYTHON_VERSION="$2"; shift 2 ;;
        --comfyui-repo) COMFYUI_REPO="$2"; shift 2 ;;
        --comfyui-ref) COMFYUI_REF="$2"; shift 2 ;;
        --nodejs-version) NODEJS_VERSION="$2"; shift 2 ;;
        --torch-version) TORCH_VERSION="$2"; shift 2 ;;
        --pip-index-url) PIP_INDEX_URL="$2"; shift 2 ;;
        --pip-extra-index-url) PIP_EXTRA_INDEX_URL="$2"; shift 2 ;;
        --pip-trusted-host) PIP_TRUSTED_HOST="$2"; shift 2 ;;
        --pytorch-index-url-override) PYTORCH_INDEX_URL_OVERRIDE="$2"; shift 2 ;;
        --push) PUSH=1; shift ;;
        --no-cache) NO_CACHE=1; shift ;;
        --test-after-build) TEST_AFTER_BUILD=1; shift ;;
        --from-env) shift ;;
        --help|-h) usage; exit 0 ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

ensure_env_file
assert_supported_host_os
resolve_python_command

RESOLVER_ARGS=(
    "${RESOLVER_SCRIPT}"
    --mode build
    --env-file "${ENV_FILE}"
    --variant "${VARIANT}"
    --build-stage "${BUILD_STAGE}"
    --plugin-manifest "${PLUGIN_MANIFEST_FILE}"
)

[[ -n "${IMAGE_NAME}" ]] && RESOLVER_ARGS+=(--image-name "${IMAGE_NAME}")
[[ -n "${CUDA_IMAGE_VERSION}" ]] && RESOLVER_ARGS+=(--cuda-image-version "${CUDA_IMAGE_VERSION}")
[[ -n "${PYTORCH_CUDA_PROFILE}" ]] && RESOLVER_ARGS+=(--pytorch-cuda-profile "${PYTORCH_CUDA_PROFILE}")
[[ -n "${UBUNTU_VERSION}" ]] && RESOLVER_ARGS+=(--ubuntu-version "${UBUNTU_VERSION}")
[[ -n "${MINIFORGE_INSTALLER_URL}" ]] && RESOLVER_ARGS+=(--miniforge-installer-url "${MINIFORGE_INSTALLER_URL}")
[[ -n "${PYTHON_VERSION}" ]] && RESOLVER_ARGS+=(--python-version "${PYTHON_VERSION}")
[[ -n "${COMFYUI_REPO}" ]] && RESOLVER_ARGS+=(--comfyui-repo "${COMFYUI_REPO}")
[[ -n "${COMFYUI_REF}" ]] && RESOLVER_ARGS+=(--comfyui-ref "${COMFYUI_REF}")
[[ -n "${NODEJS_VERSION}" ]] && RESOLVER_ARGS+=(--nodejs-version "${NODEJS_VERSION}")
[[ -n "${TORCH_VERSION}" ]] && RESOLVER_ARGS+=(--torch-version "${TORCH_VERSION}")
[[ -n "${PIP_INDEX_URL}" ]] && RESOLVER_ARGS+=(--pip-index-url "${PIP_INDEX_URL}")
[[ -n "${PIP_EXTRA_INDEX_URL}" ]] && RESOLVER_ARGS+=(--pip-extra-index-url "${PIP_EXTRA_INDEX_URL}")
[[ -n "${PIP_TRUSTED_HOST}" ]] && RESOLVER_ARGS+=(--pip-trusted-host "${PIP_TRUSTED_HOST}")
[[ -n "${PYTORCH_INDEX_URL_OVERRIDE}" ]] && RESOLVER_ARGS+=(--pytorch-index-url-override "${PYTORCH_INDEX_URL_OVERRIDE}")

eval "$("${PYTHON_BIN}" "${RESOLVER_ARGS[@]}")"
resolve_gpu_mode

if [[ "${PUSH}" -eq 1 && "${TEST_AFTER_BUILD}" -eq 1 ]]; then
    echo "test-after-build 需要本地已加载镜像，请不要和 --push 一起使用。" >&2
    exit 1
fi

LEGACY_CACHE_DIR="${SCRIPT_DIR}/.buildx-cache"
LEGACY_BOOTSTRAP_CACHE_DIR="${SCRIPT_DIR}/.buildx-cache-bootstrap"
LEGACY_FINAL_CACHE_DIR="${SCRIPT_DIR}/.buildx-cache-final"
CACHE_ROOT_DIR="${SCRIPT_DIR}/.buildx-cache-v2"
BOOTSTRAP_CACHE_PARENT_DIR="${CACHE_ROOT_DIR}/bootstrap"
FINAL_CACHE_PARENT_DIR="${CACHE_ROOT_DIR}/final"
BOOTSTRAP_CACHE_DIR="${CACHE_ROOT_DIR}/bootstrap/${CACHE_KEY_SUFFIX}"
BOOTSTRAP_CACHE_NEW_DIR="${CACHE_ROOT_DIR}/bootstrap/${CACHE_KEY_SUFFIX}-new"
FINAL_CACHE_DIR="${CACHE_ROOT_DIR}/final/${FINAL_CACHE_KEY_SUFFIX}"
FINAL_CACHE_NEW_DIR="${CACHE_ROOT_DIR}/final/${FINAL_CACHE_KEY_SUFFIX}-new"

if [[ "${BUILD_STAGE}" == "bootstrap" ]]; then
    CACHE_DIR="${BOOTSTRAP_CACHE_DIR}"
    CACHE_NEW_DIR="${BOOTSTRAP_CACHE_NEW_DIR}"
else
    CACHE_DIR="${FINAL_CACHE_DIR}"
    CACHE_NEW_DIR="${FINAL_CACHE_NEW_DIR}"
fi

mkdir -p "${BOOTSTRAP_CACHE_PARENT_DIR}" "${FINAL_CACHE_PARENT_DIR}"
rm -rf "${CACHE_NEW_DIR}"
remove_stale_new_dirs "${BOOTSTRAP_CACHE_PARENT_DIR}" "${BOOTSTRAP_CACHE_NEW_DIR}"
remove_stale_new_dirs "${FINAL_CACHE_PARENT_DIR}" "${FINAL_CACHE_NEW_DIR}"

CACHE_FROM_DIRS=()

if [[ ! -e "${BOOTSTRAP_CACHE_DIR}" && ! -e "${FINAL_CACHE_DIR}" ]] && has_buildkit_cache "${LEGACY_CACHE_DIR}"; then
    append_unique "${LEGACY_CACHE_DIR}"
fi
if [[ "${BUILD_STAGE}" == "bootstrap" && ! -e "${CACHE_DIR}" ]] && has_buildkit_cache "${LEGACY_BOOTSTRAP_CACHE_DIR}"; then
    append_unique "${LEGACY_BOOTSTRAP_CACHE_DIR}"
fi
if [[ "${BUILD_STAGE}" == "final" && ! -e "${CACHE_DIR}" ]] && has_buildkit_cache "${LEGACY_FINAL_CACHE_DIR}"; then
    append_unique "${LEGACY_FINAL_CACHE_DIR}"
fi

if [[ "${BUILD_STAGE}" == "final" && -d "${FINAL_CACHE_PARENT_DIR}" ]]; then
    shopt -s nullglob
    for related_dir in "${FINAL_CACHE_PARENT_DIR}/${CACHE_KEY_SUFFIX}"*; do
        [[ -d "${related_dir}" ]] || continue
        [[ "${related_dir}" == "${CACHE_DIR}" ]] && continue
        [[ "${related_dir}" == *-new ]] && continue
        has_buildkit_cache "${related_dir}" || continue
        append_unique "${related_dir}"
    done
    shopt -u nullglob
fi

if [[ "${BUILD_STAGE}" == "final" && -d "${BOOTSTRAP_CACHE_DIR}" ]]; then
    append_unique "${BOOTSTRAP_CACHE_DIR}"
fi
if [[ -d "${CACHE_DIR}" ]]; then
    append_unique "${CACHE_DIR}"
fi

PULL_IMAGES=("${BUILDER_CUDA_IMAGE}" "${FINAL_CUDA_IMAGE}" "${UV_IMAGE}")
for image in "${PULL_IMAGES[@]}"; do
    docker pull "${image}"
done

BUILD_ARGS=(
    buildx build
    --file "${DOCKERFILE_PATH}"
    --target "${BUILD_STAGE}"
    --tag "${IMAGE_TAG}"
    --build-arg "BUILDER_CUDA_IMAGE=${BUILDER_CUDA_IMAGE}"
    --build-arg "FINAL_CUDA_IMAGE=${FINAL_CUDA_IMAGE}"
    --build-arg "MINIFORGE_INSTALLER_URL=${MINIFORGE_INSTALLER_URL}"
    --build-arg "PYTHON_VERSION=${PYTHON_VERSION}"
    --build-arg "COMFYUI_REPO=${COMFYUI_REPO}"
    --build-arg "COMFYUI_REF=${COMFYUI_REF}"
    --build-arg "COMFYUI_RESOLVED_COMMIT=${COMFYUI_RESOLVED_COMMIT}"
    --build-arg "CUDA_PROFILE=${PYTORCH_CUDA_PROFILE}"
    --build-arg "UBUNTU_VERSION=${UBUNTU_VERSION}"
    --build-arg "UBUNTU_CACHE_KEY=${UBUNTU_CACHE_KEY}"
    --build-arg "APT_CACHE_KEY=${APT_CACHE_KEY}"
    --build-arg "CONDA_CACHE_KEY=${CONDA_CACHE_KEY}"
    --build-arg "PIP_CACHE_KEY=${PIP_CACHE_KEY}"
    --build-arg "PYTORCH_INDEX_URL=${PYTORCH_INDEX_URL}"
    --build-arg "PIP_INDEX_URL=${PIP_INDEX_URL}"
    --build-arg "PIP_EXTRA_INDEX_URL=${PIP_EXTRA_INDEX_URL}"
    --build-arg "PIP_TRUSTED_HOST=${PIP_TRUSTED_HOST}"
    --build-arg "NODEJS_VERSION=${NODEJS_VERSION}"
    --build-arg "TORCH_VERSION=${TORCH_VERSION}"
    --build-arg "TORCHVISION_VERSION=${TORCHVISION_VERSION}"
    --build-arg "TORCHAUDIO_VERSION=${TORCHAUDIO_VERSION}"
    --build-arg "XFORMERS_VERSION=${XFORMERS_VERSION}"
    --build-arg "CUSTOM_NODES_CACHE_KEY=${CUSTOM_NODES_HASH}"
    --build-arg "CUSTOM_NODES_LOCK_B64=${CUSTOM_NODES_LOCK_B64}"
)

if needs_host_gateway_alias; then
    BUILD_ARGS+=(--add-host "host.docker.internal=host-gateway")
fi

BUILD_ARGS+=(--cache-to "type=local,dest=${CACHE_NEW_DIR},mode=max")

for cache_from_dir in "${CACHE_FROM_DIRS[@]:-}"; do
    BUILD_ARGS+=(--cache-from "type=local,src=${cache_from_dir}")
done

if [[ "${PUSH}" -eq 1 ]]; then
    BUILD_ARGS+=(--push)
else
    BUILD_ARGS+=(--load)
fi

if [[ "${NO_CACHE}" -eq 1 ]]; then
    BUILD_ARGS+=(--no-cache)
fi

BUILD_ARGS+=(.)

if [[ "${BUILD_STAGE}" == "bootstrap" ]]; then
    CACHE_ROTATE_LOCK_DIR="${BOOTSTRAP_CACHE_PARENT_DIR}/.rotate.lock"
else
    CACHE_ROTATE_LOCK_DIR="${FINAL_CACHE_PARENT_DIR}/.rotate.lock"
fi

echo "[Build] IMAGE_TAG=${IMAGE_TAG}"
echo "[Build] BUILD_STAGE=${BUILD_STAGE}"
echo "[Build] VARIANT=${VARIANT}"
echo "[Build] PYTORCH_INDEX_URL=${PYTORCH_INDEX_URL}"
echo "[Build] COMFYUI_GPU_MODE=${COMFYUI_GPU_MODE}"
echo "[Build] GPU_ENABLED=${GPU_ENABLED}"
echo "[ComfyUI] RESOLVED_COMMIT=${COMFYUI_RESOLVED_COMMIT}"

(
    cd "${ROOT_DIR}"
    docker "${BUILD_ARGS[@]}"
)

(
    set -e
    acquire_buildkit_cache_lock "${CACHE_ROTATE_LOCK_DIR}"
    trap 'release_buildkit_cache_lock "${CACHE_ROTATE_LOCK_DIR}"' EXIT

    promote_buildkit_cache "${CACHE_DIR}" "${CACHE_NEW_DIR}"
    if [[ "${BUILD_STAGE}" == "final" ]]; then
        remove_sibling_caches "${FINAL_CACHE_PARENT_DIR}" "${CACHE_DIR}" "${CACHE_KEY_SUFFIX}"*
    fi
)

if [[ "${TEST_AFTER_BUILD}" -eq 1 ]]; then
    bash "${TEST_SCRIPT}" --image-tag "${IMAGE_TAG}" --build-stage "${BUILD_STAGE}" --gpu-enabled "${GPU_ENABLED}"
fi
