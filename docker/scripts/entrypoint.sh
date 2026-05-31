#!/usr/bin/env bash

set -euo pipefail

COMFYUI_HOME="${COMFYUI_HOME:-/root/ComfyUI}"
COMFYUI_SEED_DIR="/root/ComfyUI-seed"

mkdir -p "${COMFYUI_HOME}"

if [[ ! -e "${COMFYUI_HOME}/main.py" ]]; then
    cp -a "${COMFYUI_SEED_DIR}/." "${COMFYUI_HOME}/"
fi

mkdir -p "${COMFYUI_HOME}/models" "${COMFYUI_HOME}/input" "${COMFYUI_HOME}/output" "${COMFYUI_HOME}/custom_nodes"

if [[ -d "${COMFYUI_SEED_DIR}/custom_nodes" ]]; then
    while IFS= read -r -d '' seed_node_path; do
        node_name="$(basename "${seed_node_path}")"
        if [[ ! -e "${COMFYUI_HOME}/custom_nodes/${node_name}" ]]; then
            cp -a "${seed_node_path}" "${COMFYUI_HOME}/custom_nodes/${node_name}"
        fi
    done < <(find "${COMFYUI_SEED_DIR}/custom_nodes" -mindepth 1 -maxdepth 1 -print0)
fi

cd "${COMFYUI_HOME}"

if [[ $# -eq 0 ]]; then
    set -- python main.py --listen 0.0.0.0 --port "${COMFYUI_PORT:-8188}"
fi

if [[ -n "${COMFYUI_ARGS:-}" ]]; then
    read -r -a extra_args <<< "${COMFYUI_ARGS}"
    set -- "$@" "${extra_args[@]}"
fi

exec "$@"
