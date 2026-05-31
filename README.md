# He-Forge-ComfyUI Docker 构建

这个仓库用于构建内置 `ComfyUI`、`Miniforge` 和 `Python 3.12` 的 Docker 镜像，并支持在 Windows 下使用 `BuildKit` 本地缓存来复用 `apt`、`pip`、`conda` 下载内容。

## 内置内容

- `ComfyUI`：构建时直接拉取到镜像内
- `Miniforge`：默认使用官方 latest 安装地址
- `Python`：默认使用 `3.12` 前缀，由 Conda 自动解析具体小版本
- `fnm`：镜像内置，并默认安装 `Node.js 22`
- `uv`：镜像内置，可直接用于 Python 包和环境管理
- `PyTorch`：默认安装 `torch==2.7.0`、`torchvision==0.22.0`、`torchaudio==2.7.0`
- `xformers`：默认跟随 `TorchVersion` 自动解析，和 PyTorch 在同一个 pip 安装步骤里安装
- `PyTorch CUDA 源`：由 `PYTORCH_CUDA_PROFILE` 自动匹配
- `custom nodes`：默认内置 `ComfyUI Manager` 和 `ComfyUI DD Translation`

`PyTorch` 构建时只需要选择 `TorchVersion`，脚本会自动匹配对应的 `torchvision`、`torchaudio` 和 `xformers`。
`Python` 也不是锁死补丁版本，默认按 `3.12` 这样的前缀安装。
`Miniforge` 默认直接跟随官方最新发布版本。
镜像内默认使用 `root` 权限运行，`ComfyUI` 工作目录位于 `/root/ComfyUI`。
镜像内同时内置 `fnm`，并通过 `fnm install 22` 的方式安装 Node.js 22 系列。
当前 Node 只支持主版本 `22` 或 `24`。
当前和运行环境强相关的目录已经统一迁到 `/root` 体系，包含 `ComfyUI`、`ComfyUI-seed`、`miniforge`、`fnm` 与相关缓存目录。
镜像内同时内置 `uv` / `uvx`，并默认使用 `/root/.cache/uv` 作为缓存目录。
内置 custom nodes 会先安装到 `/root/ComfyUI-seed/custom_nodes`，首次启动时再随 seed 目录同步到挂载的 `/root/ComfyUI/custom_nodes`。

## 内置插件

当前插件清单位于：

```text
docker/plugins/custom-nodes.json
```

默认启用两个测试插件：

- `ComfyUI Manager`：`https://github.com/Comfy-Org/ComfyUI-Manager.git`
- `ComfyUI DD Translation`：`https://github.com/Dontdrunk/ComfyUI-DD-Translation.git`

插件安装由 `docker/scripts/install-plugins.py` 统一处理，流程为：

- 读取 `docker/plugins/custom-nodes.json`
- 构建前通过 `docker/scripts/resolve-plugin-lock.py` 把插件引用解析为真实 commit
- 克隆启用的插件到 `/root/ComfyUI-src/custom_nodes`
- 如果插件目录存在 `requirements.txt`，则自动安装依赖
- 安装插件依赖时会使用 PyTorch 相关 constraints，避免插件 requirements 意外改写 `torch`、`torchvision`、`torchaudio` 或 `xformers` 版本

插件清单和解析后的真实 commit 变化后，`final` 阶段缓存目录会自动附加插件锁哈希，例如：

```text
docker/.buildx-cache-v2/final/<版本组合>-plugins<插件锁哈希>
```

这样插件仓库即使仍然写分支名，只要上游提交变化，`final` 缓存也会自动切到新的插件锁版本；与此同时，不同插件组合不会互相覆盖最终阶段缓存，仍然可以继续复用 `bootstrap` 阶段和 PyTorch 大层缓存。
构建脚本也会尝试把同版本的旧 `final` 缓存作为 `cache-from` 来源，因此在插件清单或插件 commit 变化后，后续第一次完整构建仍有机会复用之前的 PyTorch 与 Python 依赖层，而不是全部重下。

## CUDA 与 PyTorch 源

这里有两层版本，不再硬绑定：

- `CUDA_IMAGE_VERSION`：控制 Docker 基础镜像，例如 `nvidia/cuda:12.8.2-runtime-ubuntu22.04`
- `PYTORCH_CUDA_PROFILE`：控制 PyTorch wheel 源，例如 `https://download.pytorch.org/whl/cu128`

默认推荐使用 `runtime`，`devel` 适合需要编译额外依赖或自定义节点的场景。

Docker 构建阶段会根据 `CUDA_IMAGE_VERSION` 和 `UBUNTU_VERSION` 自动选择对应的 `devel` 镜像，最终镜像再切换到你选择的 `runtime` 或 `devel`，这样更有利于编译依赖和复用缓存。
CUDA 镜像版本来自 NVIDIA 官方 `supported-tags.md` 生成的本地清单：`docker/data/cuda-tags.json`。
PyTorch 版本矩阵来自 PyTorch 官方安装文档和 `xformers` PyPI 元数据生成的本地清单：`docker/data/pytorch-tags.json`。

更新 CUDA 镜像标签清单：

```powershell
.\docker\update-cuda-tags.ps1
```

该脚本会调用 `python docker/scripts/update-cuda-tags.py` 拉取并解析 NVIDIA 官方标签文档，然后刷新 `docker/data/cuda-tags.json`。

更新 PyTorch 版本矩阵：

```powershell
.\docker\update-pytorch-tags.ps1
```

如果希望额外访问 `download.pytorch.org` wheel index 做二次确认，会同时校验 `torch` 和 `xformers` wheel 是否存在：

```powershell
.\docker\update-pytorch-tags.ps1 -VerifyWheels
```

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
- `docker/scripts/test.ps1`
- `docker/scripts/entrypoint.sh`
- `docker/scripts/install-plugins.py`
- `docker/scripts/resolve-plugin-lock.py`
- `docker/plugins/custom-nodes.json`

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
在交互模式下，脚本还会继续询问“构建完成后是否运行镜像自检”，默认会直接执行自检。

如果你想临时覆盖 `.env` 中的部分版本配置，也可以通过参数构建：

```powershell
.\docker\build.ps1 -CudaImageVersion 12.8.2 -PyTorchCudaProfile cu128 -UbuntuVersion 22.04 -TorchVersion 2.7.0
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

如果你希望跳过交互、并在构建成功后自动输出镜像自检结果，可以加 `-TestAfterBuild`：

```powershell
.\docker\build.ps1 -FromEnv -BuildStage final -TestAfterBuild
```

`bootstrap` 阶段会测试 `Python`、`Node.js`、`npm`、`uv`、`ComfyUI seed` 和 `Miniforge` 路径。
`final` 阶段会额外测试 `PyTorch`、`torchvision`、`torchaudio`、`xformers`、CUDA 可用性、GPU 名称和 `ComfyUI` Python 导入。
如果当前镜像内置了 custom nodes，自检也会检查 `ComfyUI Manager` 和 `ComfyUI DD Translation` 是否存在于 `/root/ComfyUI/custom_nodes`。

镜像 tag 会随关键版本自动变化，规则为：

```text
final:     <IMAGE_NAME>:ubuntu<UBUNTU_VERSION>-py<PYTHON_VERSION>-<PYTORCH_CUDA_PROFILE>-torch<TORCH_VERSION>-<Variant>
bootstrap: <IMAGE_NAME>:ubuntu<UBUNTU_VERSION>-py<PYTHON_VERSION>-<PYTORCH_CUDA_PROFILE>-torch<TORCH_VERSION>-bootstrap-<Variant>
```

例如默认配置会生成：

```text
hegenai/comfyui:ubuntu22.04-py312-cu128-torch2.7.0-runtime
hegenai/comfyui:ubuntu22.04-py312-cu128-torch2.7.0-bootstrap-runtime
```

构建 `devel`：

```powershell
.\docker\build.ps1 -Variant devel
```

切换 PyTorch CUDA 源：

```powershell
.\docker\build.ps1 -PyTorchCudaProfile cu126
```

固定 ComfyUI 提交或标签：

```powershell
.\docker\build.ps1 -ComfyUIRef v0.3.41
```

构建时会在 `docker/` 目录生成：

- `docker/.buildx-cache-v2/bootstrap/<版本组合>`
- `docker/.buildx-cache-v2/bootstrap/<版本组合>-new`
- `docker/.buildx-cache-v2/final/<版本组合>`
- `docker/.buildx-cache-v2/final/<版本组合>-new`

脚本会按阶段自动轮换缓存目录，避免 `final` 阶段覆盖 `bootstrap` 阶段已经跑出来的缓存。
`final` 阶段会同时读取 `bootstrap` 缓存和 `final` 缓存，但只更新 `final` 缓存。
如果你之前已经生成过旧的 `docker/.buildx-cache`，脚本会在新阶段缓存还不存在时把它作为兼容来源读取一次；新缓存统一写入 `docker/.buildx-cache-v2`，避免新旧布局混在一起。
版本组合会包含 Docker CUDA 镜像版本、PyTorch CUDA 源、Ubuntu、Torch、Python 和镜像类型，因此不同版本不会互相覆盖；相同版本组合重复构建则会复用同一个缓存。

APT 构建缓存会保留在 BuildKit cache 中，包括：

- `/var/cache/apt`
- `/var/lib/apt/lists`

因此 `apt-get update` 这条命令仍然会执行，但不会再每次从零下载完整索引和 `.deb` 包。首次成功构建后，后续重复构建会优先复用对应阶段缓存中导出的 APT 缓存。
APT cache mount 会按 `CUDA_IMAGE_VERSION + UBUNTU_VERSION` 隔离；pip cache mount 会按 `PYTHON_VERSION + TORCH_VERSION + PYTORCH_CUDA_PROFILE` 隔离；conda 包缓存会按 `PYTHON_VERSION` 隔离。
考虑到 `torch` / `torchvision` / `torchaudio` / `xformers` wheel 体积很大，当前构建还会额外把它们先下载到单独的 BuildKit wheel 缓存目录，再从本地 wheelhouse 安装。这样即使 pip 的普通 HTTP 缓存命中不稳定，后续同版本重建也能直接复用这些大文件，而不是重新完整下载。

如果你所在环境对带宽比较敏感，推荐额外配置局域网代理或镜像：

- `APT_HTTP_PROXY`
  适合接 `apt-cacher-ng`、局域网代理或上级缓存。
- `APT_HTTPS_PROXY`
  默认建议留空直连，避免 NVIDIA CUDA 这类 `https` 源被普通 HTTP 代理的 `CONNECT` 限制拦住。
- `PIP_INDEX_URL` / `PIP_EXTRA_INDEX_URL` / `PIP_TRUSTED_HOST`
  适合接 `devpi`、`Nexus`、`Artifactory` 或局域网 PyPI 镜像。
- `PYTORCH_INDEX_URL_OVERRIDE`
  如果你做了局域网 PyTorch wheel 镜像，可以直接覆盖默认的 `https://download.pytorch.org/whl/<profile>`。

例如：

```dotenv
APT_HTTP_PROXY=http://192.168.1.10:3142
APT_HTTPS_PROXY=
PIP_INDEX_URL=http://192.168.1.10:3141/root/pypi/+simple/
PIP_TRUSTED_HOST=192.168.1.10
PYTORCH_INDEX_URL_OVERRIDE=http://192.168.1.10:8080/pytorch/cu128
```

这样即使 `apt-get update` 和 `pip install` 继续执行，请求也会优先走局域网缓存，而不是每次都直接打外网。

如果你想先在本机快速挂一套缓存容器，这个仓库也内置了两个可选服务：

- `apt-cacher-ng`
- `devpi`
- `pytorch-proxy`

启动缓存服务：

```powershell
.\docker\compose.ps1 --profile cache up -d apt-cacher-ng devpi pytorch-proxy
```

然后把 `docker/.env` 改成：

```dotenv
APT_HTTP_PROXY=http://host.docker.internal:3142
APT_HTTPS_PROXY=
PIP_INDEX_URL=http://host.docker.internal:3141/root/pypi/+simple/
PIP_TRUSTED_HOST=host.docker.internal
PYTORCH_INDEX_URL_OVERRIDE=http://host.docker.internal:3143/whl/{profile}
```

这里的 `{profile}` 会在构建时自动替换成当前的 `PYTORCH_CUDA_PROFILE`，例如：

- `cu128 -> http://host.docker.internal:3143/whl/cu128`
- `cu126 -> http://host.docker.internal:3143/whl/cu126`

这样后续 `build.ps1` 再执行 `apt-get update`、`pip install`、`pip install torch... --index-url ...` 时，会优先打到你本机这些缓存容器，而不是每次都直接出公网。

## 运行方式

先复制环境变量模板：

```powershell
Copy-Item .\docker\.env.example .\docker\.env
```

如果你要切换 Docker CUDA 镜像或 PyTorch CUDA 源，只需要修改 `.env` 里的选择项：

```dotenv
CUDA_IMAGE_VERSION=12.8.2
PYTORCH_CUDA_PROFILE=cu128
UBUNTU_VERSION=22.04
```

`CUDA_VERSION` 不需要在 `.env` 里手写，构建入口会根据 `CUDA_IMAGE_VERSION` 和 `UBUNTU_VERSION` 自动推导实际基础镜像。
`PyTorch` 下载源则根据 `PYTORCH_CUDA_PROFILE` 自动推导：

- `cu128 -> https://download.pytorch.org/whl/cu128`
- `cu126 -> https://download.pytorch.org/whl/cu126`
- `cu124 -> https://download.pytorch.org/whl/cu124`
- `cu118 -> https://download.pytorch.org/whl/cu118`

`PYTORCH_CUDA_PROFILE` 和 `xformers` 会按 `TORCH_VERSION` 联动，实际可选项以 `docker/data/pytorch-tags.json` 为准。
如果 PyTorch 官方发布了新版本，运行 `.\docker\update-pytorch-tags.ps1` 后，交互菜单会自动读取新的版本矩阵。

`UBUNTU_VERSION` 填写完整 Ubuntu 版本号，当前支持：

- `22.04 -> ubuntu22.04`
- `24.04 -> ubuntu24.04`

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

如果你还希望容器运行后在镜像内继续 `pip install` 也走局域网源，可以把下面这些变量一起写进 `docker/.env`，`compose` 启动时会自动带进去：

```dotenv
PIP_INDEX_URL=http://192.168.1.10:3141/root/pypi/+simple/
PIP_EXTRA_INDEX_URL=
PIP_TRUSTED_HOST=192.168.1.10
```

注意一件事：你现在已经有运行时 `pip` 缓存挂载了，也就是：

```dotenv
RUNTIME_PIP_CACHE_DIR=../storage/runtime/cache/pip
DEVEL_PIP_CACHE_DIR=../storage/devel/cache/pip
```

这能帮助“容器启动后再手动 `pip install`”的场景复用缓存。
但 Docker 构建阶段的 `pip install` 主要还是走 BuildKit cache 和上面的 `devpi` 更有效，因为构建期并不是普通容器运行时的 bind mount 模式。

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

如果宿主机挂载目录已经存在旧的 `ComfyUI` 内容，入口脚本不会整体覆盖它；但现在会把镜像内置且当前目录中缺失的 `custom_nodes` 定向补齐进去。这样新镜像增加插件后，不需要清空整个挂载目录也能把缺失插件同步进来。

## 自定义参数

可以通过 `docker/build.ps1` 覆盖这些参数：

- `-CudaImageVersion`
- `-PyTorchCudaProfile`
- `-BuildStage`
- `-UbuntuVersion`
- `-MiniforgeInstallerUrl`
- `-PythonVersion`
- `-ComfyUIRepo`
- `-ComfyUIRef`
- `-NodeJsVersion`
- `-TorchVersion`
- `-FromEnv`
- `-TestAfterBuild`

版本配置入口为 `docker/configure.ps1`，它只负责交互式写入 `docker/.env`。
构建入口统一为 `docker/build.ps1`。直接运行 `.\docker\build.ps1` 会先确认版本配置，再选择构建阶段并开始构建。
如果要跳过所有交互并使用 `docker/.env`，使用 `.\docker\build.ps1 -FromEnv -BuildStage final` 或 `.\docker\build.ps1 -FromEnv -BuildStage bootstrap`。

`docker compose` 推荐通过 `docker/compose.ps1` 间接调用，主要负责启动、停止、查看日志等运行期操作。
`compose.ps1` 会读取 `docker/.env`，并根据 `CUDA_IMAGE_VERSION` 和 `UBUNTU_VERSION` 推导实际 CUDA 镜像标签。
同时也会根据 `CUDA_IMAGE_VERSION`、`PYTORCH_CUDA_PROFILE`、`UBUNTU_VERSION`、`TORCH_VERSION` 推导运行镜像 tag，确保 `compose` 启动的是当前版本组合对应的镜像。
其中 `docker/.env` 里只保留真正会被运行入口读取的变量；像 `COMFYUI_SEED_DIR`、`MINIFORGE_DIR`、`FNM_DIR` 这类镜像内部固定路径不再放进 `.env`，避免误导。

例如：

```powershell
.\docker\build.ps1 `
  -Variant runtime `
  -CudaImageVersion 12.8.2 `
  -PyTorchCudaProfile cu128 `
  -ComfyUIRef master `
  -MiniforgeInstallerUrl "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh" `
  -NodeJsVersion 22 `
  -TorchVersion 2.7.0
```

例如切换到另一组官方匹配版本：

```powershell
.\docker\build.ps1 `
  -Variant runtime `
  -CudaImageVersion 12.6.3 `
  -PyTorchCudaProfile cu126 `
  -TorchVersion 2.7.1
```

## 说明

- `Miniforge` 当前默认下载官方 latest 安装器；如果你需要完全可复现构建，建议把 `-MiniforgeInstallerUrl` 改成某个具体 release 的固定地址
- `Node.js` 通过镜像内置的 `fnm` 安装，默认使用 `fnm install 22`
- `NodeJsVersion` 当前只允许 `22` 或 `24`
- `uv` / `uvx` 通过官方镜像复制二进制方式内置，默认跟随 `ghcr.io/astral-sh/uv:latest`
- `PyTorch` 已在镜像构建阶段安装，不需要进入容器后再手动安装
- `build.ps1` 的 BuildKit 本地缓存保存在宿主机 `docker/.buildx-cache-v2*`，不会打进最终镜像
- `docker compose` 默认额外挂载 `pip/conda/npm/uv` 运行时缓存目录，方便容器内后续安装复用缓存，但这些缓存也不属于镜像内容
- `build.ps1` 会严格校验并映射 `TorchVersion`；具体 `torchvision/torchaudio` 由本地 PyTorch 版本矩阵统一推导
- `xformers` 会从同一份版本矩阵解析；如果当前 `TorchVersion + PYTORCH_CUDA_PROFILE` 没有匹配 wheel，则不会强行安装，避免 pip 改写 PyTorch 版本
- 构建入口统一为 `.\docker\build.ps1`，这样本地 BuildKit cache 轮换、镜像预拉取、版本校验都在一条链路里完成
- `BuildStage=bootstrap` 只预热系统、Python、ComfyUI 源码、Node 和 uv；`BuildStage=final` 才安装 PyTorch 和 ComfyUI 依赖
- 当前默认安装命令等价于 `pip install torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 xformers==0.0.30 --index-url <随 PyTorchCudaProfile 自动匹配>`
- 当前内置匹配来自 `docker/data/pytorch-tags.json`，默认包含官方页面解析到的 `torch/torchvision/torchaudio/xformers` 对应关系
- 如果你要更换 Docker CUDA 基础镜像，直接传 `-CudaImageVersion`
- 如果你要更换 PyTorch CUDA wheel 源，直接传 `-PyTorchCudaProfile`
- 如果你要更换 Node.js 主版本，直接传 `-NodeJsVersion`
- 如果你要更换版本，直接在构建时传 `-TorchVersion`
- 如果你使用 `docker compose`，推荐通过 `.\docker\compose.ps1` 调用；它只负责运行期操作，构建仍然使用 `.\docker\build.ps1`
- 如果你希望构建可复现，建议把 `ComfyUIRef` 固定为具体 tag 或 commit
- 如果你希望插件构建完全可复现，建议把 `docker/plugins/custom-nodes.json` 中每个插件的 `ref` 固定为 tag 或 commit
- 当前只保留 `runtime` 和 `devel` 两种最终镜像
