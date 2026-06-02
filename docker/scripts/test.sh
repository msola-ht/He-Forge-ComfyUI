#!/usr/bin/env bash

set -euo pipefail

IMAGE_TAG=""
BUILD_STAGE=""
GPU_ENABLED="1"

usage() {
    cat <<'EOF'
用法：
  bash docker/scripts/test.sh --image-tag <tag> --build-stage <bootstrap|final> [--gpu-enabled <0|1>]
EOF
}

docker_test_command() {
    local name="$1"
    local gpu="$2"
    shift 2

    echo
    echo "[Test] ${name}"

    local args=(run --rm)
    if [[ "${gpu}" == "1" ]]; then
        args+=(--gpus all)
    fi
    args+=("${IMAGE_TAG}")
    args+=("$@")

    docker "${args[@]}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --image-tag) IMAGE_TAG="$2"; shift 2 ;;
        --build-stage) BUILD_STAGE="$2"; shift 2 ;;
        --gpu-enabled) GPU_ENABLED="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "${IMAGE_TAG}" || -z "${BUILD_STAGE}" ]]; then
    usage >&2
    exit 1
fi

if [[ "${GPU_ENABLED}" != "0" && "${GPU_ENABLED}" != "1" ]]; then
    echo "gpu-enabled 仅支持 0 或 1，当前值：${GPU_ENABLED}" >&2
    exit 1
fi

echo
echo "[Test] 开始镜像自检：${IMAGE_TAG}（${BUILD_STAGE}）"

docker_test_command "Python 版本" 0 python --version
docker_test_command "Node.js 版本" 0 node -v
docker_test_command "npm 版本" 0 npm -v
docker_test_command "uv 版本" 0 uv --version
docker_test_command \
    "ComfyUI 种子目录与 Miniforge 路径" \
    0 \
    bash \
    -lc \
    'test -f /root/ComfyUI-seed/main.py && test -f /root/ComfyUI/main.py && test -d /root/miniforge && echo "ComfyUI seed and Miniforge OK"'

if [[ "${BUILD_STAGE}" == "final" ]]; then
    if [[ "${GPU_ENABLED}" == "1" ]]; then
        docker_test_command \
            "PyTorch CUDA 可用性" \
            1 \
            python \
            -c \
            'import torch, torchvision, torchaudio; print("torch=" + torch.__version__); print("torchvision=" + torchvision.__version__); print("torchaudio=" + torchaudio.__version__); import xformers; print("xformers=" + xformers.__version__); print("cuda_available=" + str(torch.cuda.is_available())); assert torch.cuda.is_available(), "CUDA is not available"; print("gpu=" + torch.cuda.get_device_name(0))'
    else
        echo
        echo "[Test] 跳过 PyTorch CUDA 可用性：当前 GPU 模式未启用"
    fi
    docker_test_command \
        "ComfyUI Python 导入" \
        0 \
        python \
        -c \
        'import comfy.options; print("comfy_import=ok")'
    docker_test_command \
        "内置 custom nodes 插件" \
        0 \
        bash \
        -lc \
        'seed_dir=/root/ComfyUI-seed/custom_nodes; target_dir=/root/ComfyUI/custom_nodes; test -d "$seed_dir"; missing=0; for seed_node in "$seed_dir"/*; do [ -d "$seed_node" ] || continue; node_name=$(basename "$seed_node"); if [ ! -d "$target_dir/$node_name" ]; then echo "missing custom node: $node_name" >&2; missing=1; fi; done; [ "$missing" -eq 0 ] && echo "custom_nodes=ok"'
    docker_test_command \
        "已有目录补齐缺失插件" \
        0 \
        bash \
        -lc \
        'seed_dir=/root/ComfyUI-seed/custom_nodes; target_dir=/tmp/existing-comfyui/custom_nodes; mkdir -p "$target_dir"; cp /root/ComfyUI-seed/main.py /tmp/existing-comfyui/main.py; COMFYUI_HOME=/tmp/existing-comfyui /usr/local/bin/entrypoint.sh true; missing=0; for seed_node in "$seed_dir"/*; do [ -d "$seed_node" ] || continue; node_name=$(basename "$seed_node"); if [ ! -d "$target_dir/$node_name" ]; then echo "missing synced custom node: $node_name" >&2; missing=1; fi; done; [ "$missing" -eq 0 ] && echo "existing_dir_sync=ok"'
fi

echo
echo "[Test] 镜像自检通过：${IMAGE_TAG}"
