import argparse
import importlib.metadata
import json
import shutil
import subprocess
from pathlib import Path


def run(command, cwd=None):
    print("+ " + " ".join(command), flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def load_manifest(path):
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    plugins = data.get("plugins")
    if not isinstance(plugins, list):
        raise ValueError(f"插件清单格式错误：{path}")

    return plugins


def fetch_plugin(plugin, custom_nodes_dir):
    plugin_id = plugin["id"]
    repo = plugin["repo"]
    source_ref = plugin.get("source_ref") or plugin.get("ref", "main")
    fetch_ref = plugin.get("fetch_ref") or source_ref
    resolved_commit = plugin.get("resolved_commit", "").strip()
    directory = plugin.get("directory") or plugin_id
    destination = custom_nodes_dir / directory

    if destination.exists():
        shutil.rmtree(destination)

    destination.mkdir(parents=True)
    run(["git", "init", "."], cwd=destination)
    run(["git", "remote", "add", "origin", repo], cwd=destination)
    if resolved_commit:
        try:
            run(["git", "fetch", "--depth", "1", "origin", fetch_ref], cwd=destination)
            run(["git", "checkout", "--detach", resolved_commit], cwd=destination)
        except subprocess.CalledProcessError:
            # Fallback for commit-pinned refs when a narrow fetch is not enough.
            run(["git", "fetch", "origin", "--tags", "--prune"], cwd=destination)
            run(["git", "checkout", "--detach", resolved_commit], cwd=destination)
    else:
        run(["git", "fetch", "--depth", "1", "origin", source_ref], cwd=destination)
        run(["git", "checkout", "--detach", "FETCH_HEAD"], cwd=destination)

    if plugin.get("submodules", False):
        run(["git", "submodule", "update", "--init", "--recursive", "--depth", "1"], cwd=destination)

    return destination


def install_requirements(plugin, plugin_dir, constraints_file):
    requirement_files = plugin.get("requirements_files", ["requirements.txt"])
    for requirement_file in requirement_files:
        requirement_path = plugin_dir / requirement_file
        if not requirement_path.exists():
            print(f"[Plugin] 跳过不存在的依赖文件：{plugin_dir.name}/{requirement_file}", flush=True)
            continue

        command = ["python", "-m", "pip", "install", "-r", str(requirement_path)]
        if constraints_file and constraints_file.exists():
            command += ["--constraint", str(constraints_file)]

        run(command, cwd=plugin_dir)


def write_constraints(path, versions):
    lines = []
    for package, version in versions.items():
        if version:
            lines.append(f"{package}=={version}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def resolve_installed_versions(fallback_versions):
    versions = {}
    for package, fallback_version in fallback_versions.items():
        try:
            versions[package] = importlib.metadata.version(package)
        except importlib.metadata.PackageNotFoundError:
            versions[package] = fallback_version

    return versions


def main():
    parser = argparse.ArgumentParser(description="安装 ComfyUI custom nodes 插件")
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--comfyui-dir", required=True, type=Path)
    parser.add_argument("--torch-version", default="")
    parser.add_argument("--torchvision-version", default="")
    parser.add_argument("--torchaudio-version", default="")
    parser.add_argument("--xformers-version", default="")
    args = parser.parse_args()

    custom_nodes_dir = args.comfyui_dir / "custom_nodes"
    custom_nodes_dir.mkdir(parents=True, exist_ok=True)

    constraints_file = Path("/tmp/comfyui-plugin-constraints.txt")
    write_constraints(
        constraints_file,
        resolve_installed_versions({
            "torch": args.torch_version,
            "torchvision": args.torchvision_version,
            "torchaudio": args.torchaudio_version,
            "xformers": args.xformers_version,
        }),
    )

    plugins = load_manifest(args.manifest)
    enabled_plugins = [plugin for plugin in plugins if plugin.get("enabled", True)]

    for plugin in enabled_plugins:
        print(f"[Plugin] 安装：{plugin['name']} ({plugin['id']})", flush=True)
        plugin_dir = fetch_plugin(plugin, custom_nodes_dir)
        install_requirements(plugin, plugin_dir, constraints_file)

    print(f"[Plugin] 已安装 {len(enabled_plugins)} 个插件", flush=True)


if __name__ == "__main__":
    main()
