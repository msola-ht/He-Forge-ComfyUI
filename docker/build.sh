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
NODEJS_VERSION=""
TORCH_VERSION=""
PIP_INDEX_URL=""
PIP_EXTRA_INDEX_URL=""
PIP_TRUSTED_HOST=""
PYTORCH_INDEX_URL_OVERRIDE=""
PUSH=0
NO_CACHE=0
TEST_AFTER_BUILD=0

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

eval "$(python "${RESOLVER_ARGS[@]}")"

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
    --cache-to "type=local,dest=${CACHE_NEW_DIR},mode=max"
)

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

echo "[Build] IMAGE_TAG=${IMAGE_TAG}"
echo "[Build] BUILD_STAGE=${BUILD_STAGE}"
echo "[Build] VARIANT=${VARIANT}"
echo "[Build] PYTORCH_INDEX_URL=${PYTORCH_INDEX_URL}"

(
    cd "${ROOT_DIR}"
    docker "${BUILD_ARGS[@]}"
)

rm -rf "${CACHE_DIR}"
if [[ -d "${CACHE_NEW_DIR}" ]]; then
    mv "${CACHE_NEW_DIR}" "${CACHE_DIR}"
fi

if [[ "${TEST_AFTER_BUILD}" -eq 1 ]]; then
    bash "${TEST_SCRIPT}" --image-tag "${IMAGE_TAG}" --build-stage "${BUILD_STAGE}"
fi
