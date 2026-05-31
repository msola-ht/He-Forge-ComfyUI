# syntax=docker/dockerfile:1.7-labs

ARG BUILDER_CUDA_IMAGE=nvidia/cuda:12.8.2-devel-ubuntu22.04
ARG FINAL_CUDA_IMAGE=nvidia/cuda:12.8.2-runtime-ubuntu22.04
ARG UV_IMAGE=ghcr.io/astral-sh/uv:latest

FROM ${BUILDER_CUDA_IMAGE} AS builder-bootstrap

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG MINIFORGE_INSTALLER_URL=https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
ARG PYTHON_VERSION=3.12
ARG COMFYUI_REPO=https://github.com/Comfy-Org/ComfyUI.git
ARG COMFYUI_REF=master
ARG CUDA_PROFILE=cu128
ARG UBUNTU_VERSION=22.04
ARG UBUNTU_CACHE_KEY=ubuntu2204
ARG APT_CACHE_KEY=cuda12.8.2-ubuntu2204
ARG CONDA_CACHE_KEY=conda-py312
ARG NODEJS_VERSION=22
ARG TORCH_VERSION=2.7.0
ARG TORCHVISION_VERSION=0.22.0
ARG TORCHAUDIO_VERSION=2.7.0
ARG XFORMERS_VERSION=

ENV CONDA_DIR=/root/miniforge \
    CONDA_ENV_NAME=comfyui \
    FNM_DIR=/root/.local/share/fnm \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

RUN --mount=type=cache,id=apt-cache-${APT_CACHE_KEY},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_KEY},target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        git-lfs \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        tini \
        unzip

RUN curl -fsSL -o /tmp/miniforge.sh "${MINIFORGE_INSTALLER_URL}" \
    && bash /tmp/miniforge.sh -b -p "${CONDA_DIR}" \
    && rm -f /tmp/miniforge.sh

ENV PATH=${CONDA_DIR}/bin:${PATH}

RUN --mount=type=cache,id=${CONDA_CACHE_KEY},target=/root/miniforge/pkgs,sharing=locked \
    conda config --system --set auto_update_conda false \
    && conda config --system --set channel_priority strict \
    && conda create -y -n "${CONDA_ENV_NAME}" python="${PYTHON_VERSION}" pip \
    && conda clean -afy

ENV PATH=${CONDA_DIR}/envs/${CONDA_ENV_NAME}/bin:${CONDA_DIR}/bin:${PATH}

WORKDIR /root/ComfyUI-src

RUN git init . \
    && git remote add origin "${COMFYUI_REPO}" \
    && git fetch --depth 1 origin "${COMFYUI_REF}" \
    && git checkout --detach FETCH_HEAD


FROM builder-bootstrap AS builder

ARG PIP_CACHE_KEY=pip-py312-torch2.7.0-cu128
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu128
ARG TORCH_VERSION=2.7.0
ARG TORCHVISION_VERSION=0.22.0
ARG TORCHAUDIO_VERSION=2.7.0
ARG XFORMERS_VERSION=

RUN --mount=type=cache,id=${PIP_CACHE_KEY},target=/root/.cache/pip,sharing=locked \
    python -m pip install --upgrade pip setuptools wheel \
    && PYTORCH_PACKAGES=( \
        "torch==${TORCH_VERSION}" \
        "torchvision==${TORCHVISION_VERSION}" \
        "torchaudio==${TORCHAUDIO_VERSION}" \
    ) \
    && if [[ -n "${XFORMERS_VERSION}" ]]; then PYTORCH_PACKAGES+=("xformers==${XFORMERS_VERSION}"); fi \
    && python -m pip install "${PYTORCH_PACKAGES[@]}" --index-url "${PYTORCH_INDEX_URL}" \
    && python -m pip install -r requirements.txt


FROM ${UV_IMAGE} AS uv-binary


FROM ${FINAL_CUDA_IMAGE} AS bootstrap

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive
ARG UBUNTU_VERSION=22.04
ARG UBUNTU_CACHE_KEY=ubuntu2204
ARG APT_CACHE_KEY=cuda12.8.2-ubuntu2204
ARG NODEJS_VERSION=22

ENV CONDA_DIR=/root/miniforge \
    CONDA_ENV_NAME=comfyui \
    FNM_DIR=/root/.local/share/fnm \
    UV_CACHE_DIR=/root/.cache/uv \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN --mount=type=cache,id=apt-cache-${APT_CACHE_KEY},target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=apt-lists-${APT_CACHE_KEY},target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && printf 'Binary::apt::APT::Keep-Downloaded-Packages "true";\n' > /etc/apt/apt.conf.d/keep-cache \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        ffmpeg \
        git \
        git-lfs \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        tini \
        unzip

COPY --from=builder-bootstrap /root/miniforge /root/miniforge
COPY --from=builder-bootstrap /root/ComfyUI-src /root/ComfyUI-seed
COPY --from=uv-binary /uv /usr/local/bin/uv
COPY --from=uv-binary /uvx /usr/local/bin/uvx
COPY --chmod=755 docker/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN case "${NODEJS_VERSION}" in 22|24) ;; *) echo "Unsupported NODEJS_VERSION: ${NODEJS_VERSION}. Only 22 or 24 are allowed." >&2; exit 1;; esac \
    && curl -fsSL https://fnm.vercel.app/install | bash \
    && export PATH="${FNM_DIR}:${PATH}" \
    && eval "$(fnm env --shell bash)" \
    && fnm install "${NODEJS_VERSION}" \
    && fnm default "${NODEJS_VERSION}" \
    && NODE_BIN="$(find "${FNM_DIR}/node-versions" -path "*/installation/bin/node" -type f -print -quit)" \
    && test -n "${NODE_BIN}" \
    && NODE_BIN_DIR="$(dirname "${NODE_BIN}")" \
    && ln -sf "${NODE_BIN_DIR}/node" /usr/local/bin/node \
    && ln -sf "${NODE_BIN_DIR}/npm" /usr/local/bin/npm \
    && ln -sf "${NODE_BIN_DIR}/npx" /usr/local/bin/npx \
    && if [[ -x "${NODE_BIN_DIR}/corepack" ]]; then ln -sf "${NODE_BIN_DIR}/corepack" /usr/local/bin/corepack; fi

ENV PATH=${CONDA_DIR}/envs/${CONDA_ENV_NAME}/bin:${CONDA_DIR}/bin:${PATH}
ENV COMFYUI_HOME=/root/ComfyUI

WORKDIR /root/ComfyUI

RUN mkdir -p /root/ComfyUI /root/ComfyUI-seed/models /root/ComfyUI-seed/input /root/ComfyUI-seed/output /root/ComfyUI-seed/custom_nodes /root/.cache/uv

EXPOSE 8188

VOLUME ["/root/ComfyUI"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["python", "main.py", "--listen", "0.0.0.0", "--port", "8188"]


FROM bootstrap AS final

COPY --from=builder /root/miniforge /root/miniforge
COPY --from=builder /root/ComfyUI-src /root/ComfyUI-seed
