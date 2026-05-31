import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


DEFAULT_SOURCE_URL = "https://gitlab.com/nvidia/container-images/cuda/-/raw/master/doc/supported-tags.md"
DEFAULT_UBUNTU_VERSIONS = ("22.04", "24.04")
REQUIRED_FLAVORS = ("runtime", "devel")


def parse_args():
    parser = argparse.ArgumentParser(description="更新 NVIDIA CUDA 官方镜像标签清单")
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL, help="NVIDIA supported-tags.md 原始地址")
    parser.add_argument("--output", default=None, help="输出 JSON 路径，默认写入 docker/data/cuda-tags.json")
    parser.add_argument("--ubuntu", nargs="*", default=list(DEFAULT_UBUNTU_VERSIONS), help="要保留的 Ubuntu 版本")
    return parser.parse_args()


def version_key(version):
    return tuple(int(part) for part in version.split("."))


def fetch_text(source_url):
    request = Request(source_url, headers={"User-Agent": "He-Forge-ComfyUI CUDA tag updater"})
    with urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def parse_supported_tags(markdown, ubuntu_versions):
    wanted_ubuntu = set(ubuntu_versions)
    tag_pattern = re.compile(
        r"(?<![\w.])(?P<version>\d+\.\d+\.\d+)-(?P<flavor>base|runtime|devel)-ubuntu(?P<ubuntu>\d+\.\d+)(?![\w.])"
    )
    matrix = {}

    for match in tag_pattern.finditer(markdown):
        ubuntu_version = match.group("ubuntu")
        if ubuntu_version not in wanted_ubuntu:
            continue

        version = match.group("version")
        flavor = match.group("flavor")
        matrix.setdefault(ubuntu_version, {}).setdefault(version, set()).add(flavor)

    result = {}
    for ubuntu_version in ubuntu_versions:
        versions = [
            version
            for version, flavors in matrix.get(ubuntu_version, {}).items()
            if all(flavor in flavors for flavor in REQUIRED_FLAVORS)
        ]
        result[ubuntu_version] = sorted(versions, key=version_key, reverse=True)

    return result


def main():
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    docker_dir = script_dir.parent
    output_path = Path(args.output) if args.output else docker_dir / "data" / "cuda-tags.json"

    markdown = fetch_text(args.source_url)
    ubuntu_tags = parse_supported_tags(markdown, args.ubuntu)

    if not any(ubuntu_tags.values()):
        raise RuntimeError("没有从 NVIDIA supported-tags.md 解析到可用的 Ubuntu CUDA 镜像标签")

    payload = {
        "source_url": args.source_url,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "ubuntu": ubuntu_tags,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    for ubuntu_version, versions in ubuntu_tags.items():
        print(f"Ubuntu {ubuntu_version}: {len(versions)} 个 CUDA 镜像版本")
        if versions:
            print(f"  最新：{versions[0]}")
    print(f"已写入：{output_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"更新 CUDA 镜像标签失败：{exc}", file=sys.stderr)
        sys.exit(1)
