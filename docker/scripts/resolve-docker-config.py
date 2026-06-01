import argparse
import base64
import hashlib
import json
import shlex
import subprocess
from pathlib import Path


DEFAULTS = {
    "ImageName": "hegenai/comfyui",
    "CudaImageVersion": "12.8.2",
    "PyTorchCudaProfile": "cu128",
    "UbuntuVersion": "22.04",
    "MiniforgeInstallerUrl": "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh",
    "PythonVersion": "3.12",
    "ComfyUIRepo": "https://github.com/Comfy-Org/ComfyUI.git",
    "ComfyUIRef": "master",
    "NodeJsVersion": "22",
    "TorchVersion": "2.7.0",
    "PipIndexUrl": "",
    "PipExtraIndexUrl": "",
    "PipTrustedHost": "",
    "PyTorchIndexUrlOverride": "",
}


def read_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, value = line.split("=", 1)
        values[name.strip()] = value.strip()

    return values


def use_env_value(values: dict[str, str], name: str, current: str) -> str:
    value = values.get(name, "")
    return value if value else current


def get_version_config(values: dict[str, str], overrides: dict[str, str | None]) -> dict[str, str]:
    config = {
        "ImageName": use_env_value(values, "IMAGE_NAME", DEFAULTS["ImageName"]),
        "CudaImageVersion": use_env_value(values, "CUDA_IMAGE_VERSION", DEFAULTS["CudaImageVersion"]),
        "PyTorchCudaProfile": use_env_value(
            values,
            "PYTORCH_CUDA_PROFILE",
            use_env_value(values, "CUDA_PROFILE", DEFAULTS["PyTorchCudaProfile"]),
        ),
        "UbuntuVersion": use_env_value(values, "UBUNTU_VERSION", DEFAULTS["UbuntuVersion"]),
        "MiniforgeInstallerUrl": use_env_value(
            values,
            "MINIFORGE_INSTALLER_URL",
            DEFAULTS["MiniforgeInstallerUrl"],
        ),
        "PythonVersion": use_env_value(values, "PYTHON_VERSION", DEFAULTS["PythonVersion"]),
        "ComfyUIRepo": use_env_value(values, "COMFYUI_REPO", DEFAULTS["ComfyUIRepo"]),
        "ComfyUIRef": use_env_value(values, "COMFYUI_REF", DEFAULTS["ComfyUIRef"]),
        "NodeJsVersion": use_env_value(values, "NODEJS_VERSION", DEFAULTS["NodeJsVersion"]),
        "TorchVersion": use_env_value(values, "TORCH_VERSION", DEFAULTS["TorchVersion"]),
        "PipIndexUrl": use_env_value(values, "PIP_INDEX_URL", DEFAULTS["PipIndexUrl"]),
        "PipExtraIndexUrl": use_env_value(values, "PIP_EXTRA_INDEX_URL", DEFAULTS["PipExtraIndexUrl"]),
        "PipTrustedHost": use_env_value(values, "PIP_TRUSTED_HOST", DEFAULTS["PipTrustedHost"]),
        "PyTorchIndexUrlOverride": use_env_value(
            values,
            "PYTORCH_INDEX_URL_OVERRIDE",
            DEFAULTS["PyTorchIndexUrlOverride"],
        ),
    }

    for key, value in overrides.items():
        if value is not None:
            config[key] = value

    return config


def load_json(path: Path) -> dict:
    if not path.exists():
        raise RuntimeError(f"缺少数据文件：{path}")
    return json.loads(path.read_text(encoding="utf-8"))


def get_ubuntu_version_options(cuda_data: dict) -> list[str]:
    return sorted(cuda_data["ubuntu"].keys())


def get_cuda_image_version_options(cuda_data: dict, ubuntu_version: str) -> list[str]:
    value = cuda_data["ubuntu"].get(ubuntu_version)
    if isinstance(value, list):
        return list(value)
    return [value] if value else []


def get_pytorch_cuda_profile_options(pytorch_data: dict, torch_version: str) -> list[str]:
    entry = pytorch_data["versions"].get(torch_version)
    return list(entry.get("cuda_profiles", [])) if entry else []


def get_torch_version_options(pytorch_data: dict) -> list[str]:
    return sorted(pytorch_data["versions"].keys(), key=lambda item: tuple(int(part) for part in item.split(".")), reverse=True)


def assert_ubuntu_version(cuda_data: dict, ubuntu_version: str) -> None:
    options = get_ubuntu_version_options(cuda_data)
    if ubuntu_version not in options:
        raise RuntimeError(f"不支持的 UbuntuVersion：{ubuntu_version}。当前支持：{', '.join(options)}")


def assert_cuda_image_version(cuda_data: dict, cuda_image_version: str, ubuntu_version: str) -> None:
    assert_ubuntu_version(cuda_data, ubuntu_version)
    options = get_cuda_image_version_options(cuda_data, ubuntu_version)
    if cuda_image_version not in options:
        raise RuntimeError(
            f"不支持的 CUDA_IMAGE_VERSION：{cuda_image_version}。Ubuntu {ubuntu_version} 当前支持：{', '.join(options)}"
        )


def assert_torch_version(pytorch_data: dict, torch_version: str) -> None:
    options = get_torch_version_options(pytorch_data)
    if torch_version not in options:
        raise RuntimeError(f"不支持的 TorchVersion：{torch_version}。当前支持：{', '.join(options)}")


def assert_nodejs_version(nodejs_version: str) -> None:
    options = ["22", "24"]
    if nodejs_version not in options:
        raise RuntimeError(f"不支持的 NodeJsVersion：{nodejs_version}。当前支持：{', '.join(options)}")


def assert_pytorch_cuda_profile(pytorch_data: dict, profile: str, torch_version: str) -> None:
    options = get_pytorch_cuda_profile_options(pytorch_data, torch_version)
    if profile not in options:
        raise RuntimeError(
            f"不支持的 PyTorchCudaProfile：{profile}。Torch {torch_version} 当前支持：{', '.join(options)}"
        )


def resolve_pytorch_index_url(pytorch_data: dict, profile: str, torch_version: str) -> str:
    assert_pytorch_cuda_profile(pytorch_data, profile, torch_version)
    return f"https://download.pytorch.org/whl/{profile}"


def resolve_pytorch_package_versions(pytorch_data: dict, torch_version: str) -> dict[str, str]:
    assert_torch_version(pytorch_data, torch_version)
    entry = pytorch_data["versions"][torch_version]
    xformers_entry = entry.get("xformers") or {}
    return {
        "TorchVersion": torch_version,
        "TorchVisionVersion": entry["torchvision"],
        "TorchAudioVersion": entry["torchaudio"],
        "XformersVersion": xformers_entry.get("version", ""),
    }


def resolve_xformers_version(pytorch_data: dict, torch_version: str, profile: str) -> str:
    assert_pytorch_cuda_profile(pytorch_data, profile, torch_version)
    entry = pytorch_data["versions"][torch_version]
    xformers_entry = entry.get("xformers")
    if not xformers_entry:
        return ""
    if profile not in xformers_entry.get("cuda_profiles", []):
        return ""
    return xformers_entry["version"]


def resolve_cuda_image_set(cuda_data: dict, cuda_image_version: str, ubuntu_version: str, variant: str) -> dict[str, str]:
    assert_cuda_image_version(cuda_data, cuda_image_version, ubuntu_version)
    ubuntu_image_tag = f"ubuntu{ubuntu_version}"
    ubuntu_cache_key = f"ubuntu{ubuntu_version.replace('.', '')}"
    return {
        "CudaVersion": cuda_image_version,
        "UbuntuCacheKey": ubuntu_cache_key,
        "BuilderCudaImage": f"nvidia/cuda:{cuda_image_version}-devel-{ubuntu_image_tag}",
        "RuntimeCudaImage": f"nvidia/cuda:{cuda_image_version}-runtime-{ubuntu_image_tag}",
        "DevelCudaImage": f"nvidia/cuda:{cuda_image_version}-devel-{ubuntu_image_tag}",
        "FinalCudaImage": f"nvidia/cuda:{cuda_image_version}-{variant}-{ubuntu_image_tag}",
    }


def resolve_image_tag_suffix(
    cuda_data: dict,
    pytorch_data: dict,
    cuda_image_version: str,
    profile: str,
    ubuntu_version: str,
    torch_version: str,
    python_version: str,
    variant: str,
    build_stage: str,
) -> str:
    assert_cuda_image_version(cuda_data, cuda_image_version, ubuntu_version)
    assert_torch_version(pytorch_data, torch_version)
    assert_pytorch_cuda_profile(pytorch_data, profile, torch_version)
    safe_python_version = python_version.replace(".", "")
    suffix = f"ubuntu{ubuntu_version}-py{safe_python_version}-{profile}-torch{torch_version}"
    return f"{suffix}-bootstrap-{variant}" if build_stage == "bootstrap" else f"{suffix}-{variant}"


def resolve_cache_key_suffix(
    cuda_image_version: str,
    profile: str,
    ubuntu_version: str,
    torch_version: str,
    python_version: str,
    variant: str,
) -> str:
    safe_python_version = python_version.replace(".", "")
    return f"cuda{cuda_image_version}-{profile}-ubuntu{ubuntu_version}-torch{torch_version}-{variant}-py{safe_python_version}"


def resolve_plugin_lock(manifest_path: Path, script_path: Path) -> str:
    result = subprocess.run(
        ["python", str(script_path), "--manifest", str(manifest_path)],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        message = result.stderr.strip() or result.stdout.strip() or "未知错误"
        raise RuntimeError(f"解析插件引用失败：{message}")
    return result.stdout.strip()


def to_shell_lines(values: dict[str, str]) -> str:
    lines = []
    for key in sorted(values.keys()):
        lines.append(f"{key}={shlex.quote(str(values[key]))}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="解析 Docker 构建与运行所需配置")
    parser.add_argument("--mode", choices=["build", "compose"], required=True)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--variant", choices=["runtime", "devel"], default="runtime")
    parser.add_argument("--build-stage", choices=["bootstrap", "final"], default="final")
    parser.add_argument("--plugin-manifest", type=Path)
    parser.add_argument("--image-name")
    parser.add_argument("--cuda-image-version")
    parser.add_argument("--pytorch-cuda-profile")
    parser.add_argument("--ubuntu-version")
    parser.add_argument("--miniforge-installer-url")
    parser.add_argument("--python-version")
    parser.add_argument("--comfyui-repo")
    parser.add_argument("--comfyui-ref")
    parser.add_argument("--nodejs-version")
    parser.add_argument("--torch-version")
    parser.add_argument("--pip-index-url")
    parser.add_argument("--pip-extra-index-url")
    parser.add_argument("--pip-trusted-host")
    parser.add_argument("--pytorch-index-url-override")
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    root_dir = Path(__file__).resolve().parents[1]
    cuda_data = load_json(root_dir / "data/cuda-tags.json")
    pytorch_data = load_json(root_dir / "data/pytorch-tags.json")
    env_values = read_env_file(args.env_file)
    overrides = {
        "ImageName": args.image_name,
        "CudaImageVersion": args.cuda_image_version,
        "PyTorchCudaProfile": args.pytorch_cuda_profile,
        "UbuntuVersion": args.ubuntu_version,
        "MiniforgeInstallerUrl": args.miniforge_installer_url,
        "PythonVersion": args.python_version,
        "ComfyUIRepo": args.comfyui_repo,
        "ComfyUIRef": args.comfyui_ref,
        "NodeJsVersion": args.nodejs_version,
        "TorchVersion": args.torch_version,
        "PipIndexUrl": args.pip_index_url,
        "PipExtraIndexUrl": args.pip_extra_index_url,
        "PipTrustedHost": args.pip_trusted_host,
        "PyTorchIndexUrlOverride": args.pytorch_index_url_override,
    }
    config = get_version_config(env_values, overrides)

    assert_ubuntu_version(cuda_data, config["UbuntuVersion"])
    assert_cuda_image_version(cuda_data, config["CudaImageVersion"], config["UbuntuVersion"])
    assert_nodejs_version(config["NodeJsVersion"])
    assert_torch_version(pytorch_data, config["TorchVersion"])
    assert_pytorch_cuda_profile(pytorch_data, config["PyTorchCudaProfile"], config["TorchVersion"])

    cuda_image_set = resolve_cuda_image_set(
        cuda_data,
        config["CudaImageVersion"],
        config["UbuntuVersion"],
        args.variant,
    )
    pytorch_index_url = (
        config["PyTorchIndexUrlOverride"]
        .replace("{profile}", config["PyTorchCudaProfile"])
        .replace("{cuda_profile}", config["PyTorchCudaProfile"])
        if config["PyTorchIndexUrlOverride"]
        else resolve_pytorch_index_url(
            pytorch_data,
            config["PyTorchCudaProfile"],
            config["TorchVersion"],
        )
    )
    package_versions = resolve_pytorch_package_versions(pytorch_data, config["TorchVersion"])
    xformers_version = resolve_xformers_version(
        pytorch_data,
        config["TorchVersion"],
        config["PyTorchCudaProfile"],
    )
    apt_cache_key = f"cuda{config['CudaImageVersion']}-{cuda_image_set['UbuntuCacheKey']}"
    conda_cache_key = f"conda-py{config['PythonVersion'].replace('.', '')}"
    pip_cache_key = (
        f"pip-py{config['PythonVersion'].replace('.', '')}-"
        f"torch{config['TorchVersion']}-{config['PyTorchCudaProfile']}"
    )
    runtime_image_tag = resolve_image_tag_suffix(
        cuda_data,
        pytorch_data,
        config["CudaImageVersion"],
        config["PyTorchCudaProfile"],
        config["UbuntuVersion"],
        config["TorchVersion"],
        config["PythonVersion"],
        "runtime",
        "final",
    )
    devel_image_tag = resolve_image_tag_suffix(
        cuda_data,
        pytorch_data,
        config["CudaImageVersion"],
        config["PyTorchCudaProfile"],
        config["UbuntuVersion"],
        config["TorchVersion"],
        config["PythonVersion"],
        "devel",
        "final",
    )

    values = {
        "IMAGE_NAME": config["ImageName"],
        "CUDA_IMAGE_VERSION": config["CudaImageVersion"],
        "PYTORCH_CUDA_PROFILE": config["PyTorchCudaProfile"],
        "UBUNTU_VERSION": config["UbuntuVersion"],
        "MINIFORGE_INSTALLER_URL": config["MiniforgeInstallerUrl"],
        "PYTHON_VERSION": config["PythonVersion"],
        "COMFYUI_REPO": config["ComfyUIRepo"],
        "COMFYUI_REF": config["ComfyUIRef"],
        "NODEJS_VERSION": config["NodeJsVersion"],
        "TORCH_VERSION": config["TorchVersion"],
        "PIP_INDEX_URL": config["PipIndexUrl"],
        "PIP_EXTRA_INDEX_URL": config["PipExtraIndexUrl"],
        "PIP_TRUSTED_HOST": config["PipTrustedHost"],
        "PYTORCH_INDEX_URL_OVERRIDE": config["PyTorchIndexUrlOverride"],
        "CUDA_VERSION": cuda_image_set["CudaVersion"],
        "UBUNTU_CACHE_KEY": cuda_image_set["UbuntuCacheKey"],
        "APT_CACHE_KEY": apt_cache_key,
        "CONDA_CACHE_KEY": conda_cache_key,
        "PIP_CACHE_KEY": pip_cache_key,
        "PYTORCH_INDEX_URL": pytorch_index_url,
        "TORCHVISION_VERSION": package_versions["TorchVisionVersion"],
        "TORCHAUDIO_VERSION": package_versions["TorchAudioVersion"],
        "XFORMERS_VERSION": xformers_version,
        "BUILDER_CUDA_IMAGE": cuda_image_set["BuilderCudaImage"],
        "RUNTIME_CUDA_IMAGE": cuda_image_set["RuntimeCudaImage"],
        "DEVEL_CUDA_IMAGE": cuda_image_set["DevelCudaImage"],
        "FINAL_CUDA_IMAGE": cuda_image_set["FinalCudaImage"],
        "RUNTIME_IMAGE_TAG": runtime_image_tag,
        "DEVEL_IMAGE_TAG": devel_image_tag,
        "VARIANT": args.variant,
        "BUILD_STAGE": args.build_stage,
        "UV_IMAGE": "ghcr.io/astral-sh/uv:latest",
    }

    if args.mode == "build":
        tag_suffix = resolve_image_tag_suffix(
            cuda_data,
            pytorch_data,
            config["CudaImageVersion"],
            config["PyTorchCudaProfile"],
            config["UbuntuVersion"],
            config["TorchVersion"],
            config["PythonVersion"],
            args.variant,
            args.build_stage,
        )
        cache_key_suffix = resolve_cache_key_suffix(
            config["CudaImageVersion"],
            config["PyTorchCudaProfile"],
            config["UbuntuVersion"],
            config["TorchVersion"],
            config["PythonVersion"],
            args.variant,
        )
        plugin_lock_json = '{"plugins":[]}'
        if args.build_stage == "final":
            manifest_path = args.plugin_manifest or (root_dir / "plugins/custom-nodes.json")
            plugin_lock_json = resolve_plugin_lock(manifest_path, root_dir / "scripts/resolve-plugin-lock.py")
        plugin_hash = hashlib.sha256(plugin_lock_json.encode("utf-8")).hexdigest()[:12].lower()
        plugin_lock_b64 = base64.b64encode(plugin_lock_json.encode("utf-8")).decode("ascii")
        values.update(
            {
                "TAG_SUFFIX": tag_suffix,
                "IMAGE_TAG": f"{config['ImageName']}:{tag_suffix}",
                "CACHE_KEY_SUFFIX": cache_key_suffix,
                "CUSTOM_NODES_HASH": plugin_hash,
                "CUSTOM_NODES_LOCK_B64": plugin_lock_b64,
                "FINAL_CACHE_KEY_SUFFIX": f"{cache_key_suffix}-plugins{plugin_hash}",
            }
        )

    print(to_shell_lines(values))


if __name__ == "__main__":
    main()
