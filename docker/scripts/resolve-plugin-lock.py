import argparse
import json
import re
import subprocess
from pathlib import Path


COMMIT_PATTERN = re.compile(r"^[0-9a-fA-F]{7,40}$")


def run(command):
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return result.stdout


def load_manifest(path):
    with path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    plugins = data.get("plugins")
    if not isinstance(plugins, list):
        raise ValueError(f"插件清单格式错误：{path}")

    return plugins


def resolve_ref(repo, source_ref):
    if COMMIT_PATTERN.fullmatch(source_ref):
        return {
            "fetch_ref": source_ref,
            "resolved_commit": source_ref.lower(),
        }

    candidate_refs = []
    if source_ref.startswith("refs/"):
        candidate_refs.append(source_ref)
    else:
        candidate_refs.append(f"refs/heads/{source_ref}")
        candidate_refs.append(f"refs/tags/{source_ref}")

    for candidate_ref in candidate_refs:
        output = run(["git", "ls-remote", "--refs", repo, candidate_ref])
        lines = [line.strip() for line in output.splitlines() if line.strip()]
        for line in lines:
            commit, resolved_ref = line.split("\t", 1)
            if resolved_ref == candidate_ref:
                return {
                    "fetch_ref": resolved_ref,
                    "resolved_commit": commit.lower(),
                }

    raise RuntimeError(f"无法精确解析插件引用：{repo} {source_ref}")


def build_lock(plugins):
    lock_plugins = []
    for plugin in plugins:
        if not plugin.get("enabled", True):
            continue

        source_ref = plugin.get("ref", "main")
        resolved = resolve_ref(plugin["repo"], source_ref)
        lock_plugins.append(
            {
                "id": plugin["id"],
                "name": plugin["name"],
                "repo": plugin["repo"],
                "directory": plugin.get("directory") or plugin["id"],
                "source_ref": source_ref,
                "fetch_ref": resolved["fetch_ref"],
                "resolved_commit": resolved["resolved_commit"],
                "requirements_files": plugin.get("requirements_files", ["requirements.txt"]),
                "submodules": plugin.get("submodules", False),
                "enabled": True,
            }
        )

    return {"plugins": lock_plugins}


def main():
    parser = argparse.ArgumentParser(description="解析 ComfyUI 插件引用并生成构建锁")
    parser.add_argument("--manifest", required=True, type=Path)
    args = parser.parse_args()

    plugins = load_manifest(args.manifest)
    lock = build_lock(plugins)
    print(json.dumps(lock, ensure_ascii=True, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
