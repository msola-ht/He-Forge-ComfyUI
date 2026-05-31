# He-Forge-ComfyUI Docker 构建

这个仓库用于构建内置 `ComfyUI`、`Miniforge` 和 `Python 3.12` 的 Docker 镜像，并支持在 Windows 下使用 `BuildKit` 本地缓存来复用 `apt`、`pip`、`conda` 下载内容。

## 内置内容

- `ComfyUI`：构建时直接拉取到镜像内
- `Miniforge`：默认使用官方 latest 安装地址
- `Python`：默认使用 `3.12` 前缀，由 Conda 自动解析具体小版本
- `fnm`：镜像内置，并默认安装 `Node.js 22`
- `uv`：镜像内置，可直接用于 Python 包和环境管理
- `PyTorch`：默认安装 `torch==2.7.0`、`torchvision==0.22.0`、`torchaudio==2.7.0`
- `PyTorch CUDA 源`：由 `CudaProfile` 自动匹配

`PyTorch` 构建时只需要选择 `TorchVersion`，脚本会自动匹配对应的 `torchvision` 和 `torchaudio`。
`Python` 也不是锁死补丁版本，默认按 `3.12` 这样的前缀安装。
`Miniforge` 默认直接跟随官方最新发布版本。
镜像内默认使用 `root` 权限运行，`ComfyUI` 工作目录位于 `/root/ComfyUI`。
镜像内同时内置 `fnm`，并通过 `fnm install 22` 的方式安装 Node.js 22 系列。
当前 Node 只支持主版本 `22` 或 `24`。
当前和运行环境强相关的目录已经统一迁到 `/root` 体系，包含 `ComfyUI`、`ComfyUI-seed`、`miniforge`、`fnm` 与相关缓存目录。
镜像内同时内置 `uv` / `uvx`，并默认使用 `/root/.cache/uv` 作为缓存目录。

## CUDA 配置

- `cu128`
  - Docker 镜像：`nvidia/cuda:12.8.2-*-ubuntu<UBUNTU_VERSION>.04`
  - PyTorch 源：`https://download.pytorch.org/whl/cu128`
- `cu126`
  - Docker 镜像：`nvidia/cuda:12.6.3-*-ubuntu<UBUNTU_VERSION>.04`
  - PyTorch 源：`https://download.pytorch.org/whl/cu126`

默认推荐使用 `runtime`，`devel` 适合需要编译额外依赖或自定义节点的场景。

Docker 构建阶段会根据 `CudaProfile` 自动选择对应的 `devel` 镜像，最终镜像再切换到你选择的 `runtime` 或 `devel`，这样更有利于编译依赖和复用缓存。

## 目录结构

Docker 相关文件已经集中到 `docker/` 目录，推荐结构如下：

- `docker/Dockerfile`
- `docker/build.ps1`
- `docker/configure.ps1`
- `docker/compose.ps1`
- `docker/docker-compose.yml`
- `docker/.env.example`
- `docker/scripts/env.ps1`
- `docker/scripts/versions.ps1`
- `docker/scripts/prompt.ps1`
- `docker/scripts/cache.ps1`
- `docker/scripts/entrypoint.sh`

## 关键目录

### 容器内目录

- `COMFYUI_HOME=/root/ComfyUI`
- `COMFYUI_SEED_DIR=/root/ComfyUI-seed`
- `MINIFORGE_DIR=/root/miniforge`
- `FNM_DIR=/root/.local/share/fnm`
- Builder 阶段源码目录：`/root/ComfyUI-src`

### 宿主机挂载目录

- `RUNTIME_COMFYUI_DIR=../storage/runtime/ComfyUI`
- `DEVEL_COMFYUI_DIR=../storage/devel/ComfyUI`
- `RUNTIME_PIP_CACHE_DIR=../storage/runtime/cache/pip`
- `RUNTIME_CONDA_CACHE_DIR=../storage/runtime/cache/conda-pkgs`
- `RUNTIME_NPM_CACHE_DIR=../storage/runtime/cache/npm`
- `RUNTIME_UV_CACHE_DIR=../storage/runtime/cache/uv`
- `DEVEL_PIP_CACHE_DIR=../storage/devel/cache/pip`
- `DEVEL_CONDA_CACHE_DIR=../storage/devel/cache/conda-pkgs`
- `DEVEL_NPM_CACHE_DIR=../storage/devel/cache/npm`
- `DEVEL_UV_CACHE_DIR=../storage/devel/cache/uv`

### 维护建议

- 运行态相关目录统一保持在 `/root` 体系下，避免同时混用 `/opt`、`/workspace`
- 如果你要改挂载位置，优先修改 `.env` 里的 `RUNTIME_COMFYUI_DIR`、`DEVEL_COMFYUI_DIR`
- 如果你要改容器内工作目录，优先修改 `.env` 里的 `COMFYUI_HOME`
- 运行时缓存建议单独挂载，不要把下载缓存烘焙进最终镜像

## 构建镜像

推荐先确认 Docker Desktop 已启用 `buildx` 和 `BuildKit`。

日常只需要运行一个入口：

```powershell
.\docker\build.ps1
```

`build.ps1` 会读取当前 `docker/.env`，先询问是否修改版本配置；如果修改，会保存回 `docker/.env`，然后继续询问这次要跑 `bootstrap` 还是 `final`，最后直接开始构建。

如果你想临时覆盖 `.env` 中的部分版本配置，也可以通过参数构建：

```powershell
.\docker\build.ps1 -CudaProfile cu128 -UbuntuVersion 22 -TorchVersion 2.7.0
```

如果你想先预热系统和基础工具层，不安装 `PyTorch` 和 `ComfyUI requirements`，可以先构建 `bootstrap`：

```powershell
.\docker\build.ps1 -FromEnv -BuildStage bootstrap
```

`bootstrap` 会完成：

- APT update/install
- Miniforge 和 Python 环境
- ComfyUI 源码克隆
- Node.js/fnm
- uv/uvx

完整镜像再跑：

```powershell
.\docker\build.ps1 -FromEnv -BuildStage final
```

构建 `devel`：

```powershell
.\docker\build.ps1 -Variant devel
```

切换 CUDA 配置：

```powershell
.\docker\build.ps1 -CudaProfile cu126
```

固定 ComfyUI 提交或标签：

```powershell
.\docker\build.ps1 -ComfyUIRef v0.3.41
```

构建时会在 `docker/` 目录生成：

- `docker/.buildx-cache-bootstrap`
- `docker/.buildx-cache-bootstrap-new`
- `docker/.buildx-cache-final`
- `docker/.buildx-cache-final-new`

脚本会按阶段自动轮换缓存目录，避免 `final` 阶段覆盖 `bootstrap` 阶段已经跑出来的缓存。
`final` 阶段会同时读取 `bootstrap` 缓存和 `final` 缓存，但只更新 `final` 缓存。
如果你之前已经生成过旧的 `docker/.buildx-cache`，脚本会在新阶段缓存还不存在时把它作为兼容来源读取一次。

APT 构建缓存会保留在 BuildKit cache 中，包括：

- `/var/cache/apt`
- `/var/lib/apt/lists`

因此 `apt-get update` 这条命令仍然会执行，但不会再每次从零下载完整索引和 `.deb` 包。首次成功构建后，后续重复构建会优先复用对应阶段缓存中导出的 APT 缓存。

## 运行方式

先复制环境变量模板：

```powershell
Copy-Item .\docker\.env.example .\docker\.env
```

如果你要切换 CUDA 配置，例如改成 `cu126`，只需要修改 `.env` 里的选择项：

```dotenv
CUDA_PROFILE=cu126
UBUNTU_VERSION=22
```

`CUDA_VERSION` 和 `PyTorch` 下载源不需要在 `.env` 里手写，构建入口会根据 `CUDA_PROFILE` 自动推导：

- `cu128 -> CUDA 12.8.2`
- `cu126 -> CUDA 12.6.3`
- `cu128 -> https://download.pytorch.org/whl/cu128`
- `cu126 -> https://download.pytorch.org/whl/cu126`

`UBUNTU_VERSION` 只填写主版本号，当前支持：

- `22 -> ubuntu22.04`
- `24 -> ubuntu24.04`

如果你要改 ComfyUI 挂载目录，也可以直接在 `.env` 里改：

```dotenv
COMFYUI_HOME=/root/ComfyUI
RUNTIME_COMFYUI_DIR=../storage/runtime/ComfyUI
DEVEL_COMFYUI_DIR=../storage/devel/ComfyUI
```

如果你要保留容器内后续安装使用的缓存，默认也已经提供独立挂载目录：

```dotenv
PIP_CACHE_DIR=/root/.cache/pip
CONDA_PKGS_DIRS=/root/miniforge/pkgs
NPM_CONFIG_CACHE=/root/.npm
UV_CACHE_DIR=/root/.cache/uv
RUNTIME_PIP_CACHE_DIR=../storage/runtime/cache/pip
RUNTIME_CONDA_CACHE_DIR=../storage/runtime/cache/conda-pkgs
RUNTIME_NPM_CACHE_DIR=../storage/runtime/cache/npm
RUNTIME_UV_CACHE_DIR=../storage/runtime/cache/uv
DEVEL_PIP_CACHE_DIR=../storage/devel/cache/pip
DEVEL_CONDA_CACHE_DIR=../storage/devel/cache/conda-pkgs
DEVEL_NPM_CACHE_DIR=../storage/devel/cache/npm
DEVEL_UV_CACHE_DIR=../storage/devel/cache/uv
```

启动 `runtime`：

```powershell
.\docker\compose.ps1 up comfyui-runtime
```

启动 `devel`：

```powershell
.\docker\compose.ps1 up comfyui-devel
```

默认端口：

- `runtime`: `8188`
- `devel`: `8190`

## 数据挂载

`docker/docker-compose.yml` 默认挂载整个 `ComfyUI` 工作目录：

- `${RUNTIME_COMFYUI_DIR} -> ${COMFYUI_HOME}`
- `${DEVEL_COMFYUI_DIR} -> ${COMFYUI_HOME}`

同时默认挂载运行时缓存目录：

- `${RUNTIME_PIP_CACHE_DIR} -> ${PIP_CACHE_DIR}`
- `${RUNTIME_CONDA_CACHE_DIR} -> ${CONDA_PKGS_DIRS}`
- `${RUNTIME_NPM_CACHE_DIR} -> ${NPM_CONFIG_CACHE}`
- `${RUNTIME_UV_CACHE_DIR} -> ${UV_CACHE_DIR}`
- `${DEVEL_PIP_CACHE_DIR} -> ${PIP_CACHE_DIR}`
- `${DEVEL_CONDA_CACHE_DIR} -> ${CONDA_PKGS_DIRS}`
- `${DEVEL_NPM_CACHE_DIR} -> ${NPM_CONFIG_CACHE}`
- `${DEVEL_UV_CACHE_DIR} -> ${UV_CACHE_DIR}`

首次启动时，如果挂载目录是空的，容器会自动把镜像内置的 `ComfyUI` 初始化进去。之后你就可以直接在宿主机上看到完整的 `ComfyUI` 目录，包括：

- `models`
- `input`
- `output`
- `custom_nodes`
- `main.py`
- 以及其余源码文件

## 自定义参数

可以通过 `docker/build.ps1` 覆盖这些参数：

- `-CudaProfile`
- `-BuildStage`
- `-UbuntuVersion`
- `-MiniforgeInstallerUrl`
- `-PythonVersion`
- `-ComfyUIRepo`
- `-ComfyUIRef`
- `-NodeJsVersion`
- `-TorchVersion`
- `-FromEnv`

版本配置入口为 `docker/configure.ps1`，它只负责交互式写入 `docker/.env`。
构建入口统一为 `docker/build.ps1`。直接运行 `.\docker\build.ps1` 会先确认版本配置，再选择构建阶段并开始构建。
如果要跳过所有交互并使用 `docker/.env`，使用 `.\docker\build.ps1 -FromEnv -BuildStage final` 或 `.\docker\build.ps1 -FromEnv -BuildStage bootstrap`。

`docker compose` 推荐通过 `docker/compose.ps1` 间接调用，主要负责启动、停止、查看日志等运行期操作。
`compose.ps1` 会读取 `docker/.env`，并根据 `CUDA_PROFILE` 和 `UBUNTU_VERSION` 推导实际 CUDA 镜像标签。
其中 `docker/.env` 里只保留真正会被运行入口读取的变量；像 `COMFYUI_SEED_DIR`、`MINIFORGE_DIR`、`FNM_DIR` 这类镜像内部固定路径不再放进 `.env`，避免误导。

例如：

```powershell
.\docker\build.ps1 `
  -Variant runtime `
  -CudaProfile cu128 `
  -ComfyUIRef master `
  -MiniforgeInstallerUrl "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh" `
  -NodeJsVersion 22 `
  -TorchVersion 2.7.0
```

例如切换到另一组官方匹配版本：

```powershell
.\docker\build.ps1 `
  -Variant runtime `
  -CudaProfile cu126 `
  -TorchVersion 2.7.1
```

## 说明

- `Miniforge` 当前默认下载官方 latest 安装器；如果你需要完全可复现构建，建议把 `-MiniforgeInstallerUrl` 改成某个具体 release 的固定地址
- `Node.js` 通过镜像内置的 `fnm` 安装，默认使用 `fnm install 22`
- `NodeJsVersion` 当前只允许 `22` 或 `24`
- `uv` / `uvx` 通过官方镜像复制二进制方式内置，默认跟随 `ghcr.io/astral-sh/uv:latest`
- `PyTorch` 已在镜像构建阶段安装，不需要进入容器后再手动安装
- `build.ps1` 的 BuildKit 本地缓存保存在宿主机 `docker/.buildx-cache*`，不会打进最终镜像
- `docker compose` 默认额外挂载 `pip/conda/npm/uv` 运行时缓存目录，方便容器内后续安装复用缓存，但这些缓存也不属于镜像内容
- `build.ps1` 会严格校验并映射 `TorchVersion`；具体 `torchvision/torchaudio` 由 Dockerfile 内部统一推导
- 构建入口统一为 `.\docker\build.ps1`，这样本地 BuildKit cache 轮换、镜像预拉取、版本校验都在一条链路里完成
- `BuildStage=bootstrap` 只预热系统、Python、ComfyUI 源码、Node 和 uv；`BuildStage=final` 才安装 PyTorch 和 ComfyUI 依赖
- 当前默认安装命令等价于 `pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 --index-url <随 CudaProfile 自动匹配>`
- 当前内置匹配：
- `2.7.1 -> torchvision 0.22.1 -> torchaudio 2.7.1`
- `2.7.0 -> torchvision 0.22.0 -> torchaudio 2.7.0`
- `2.6.0 -> torchvision 0.21.0 -> torchaudio 2.6.0`
- 如果你要更换 CUDA 与 Docker 基础镜像，直接传 `-CudaProfile`
- 如果你要更换 Node.js 主版本，直接传 `-NodeJsVersion`
- 如果你要更换版本，直接在构建时传 `-TorchVersion`
- 如果你使用 `docker compose`，推荐通过 `.\docker\compose.ps1` 调用；它只负责运行期操作，构建仍然使用 `.\docker\build.ps1`
- 如果你希望构建可复现，建议把 `ComfyUIRef` 固定为具体 tag 或 commit
- 当前只保留 `runtime` 和 `devel` 两种最终镜像
