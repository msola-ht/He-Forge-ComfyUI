import argparse
import json
import sys
import re
from html import unescape
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen


DEFAULT_LOCALLY_URL = "https://pytorch.org/get-started/locally/"
DEFAULT_PREVIOUS_URL = "https://pytorch.org/get-started/previous-versions/"
DEFAULT_XFORMERS_URL = "https://pypi.org/pypi/xformers/json"


def parse_args():
    parser = argparse.ArgumentParser(description="更新 PyTorch pip wheel 版本矩阵")
    parser.add_argument("--locally-url", default=DEFAULT_LOCALLY_URL, help="PyTorch 当前安装页面")
    parser.add_argument("--previous-url", default=DEFAULT_PREVIOUS_URL, help="PyTorch 历史版本页面")
    parser.add_argument("--xformers-url", default=DEFAULT_XFORMERS_URL, help="xformers PyPI JSON 元数据地址")
    parser.add_argument("--output", default=None, help="输出 JSON 路径，默认写入 docker/data/pytorch-tags.json")
    parser.add_argument("--min-version", default="2.6.0", help="保留的最低 torch 版本")
    parser.add_argument("--verify-wheels", action="store_true", help="从 download.pytorch.org wheel index 二次确认 torch wheel 存在")
    return parser.parse_args()


def version_key(version):
    main, _, post = version.partition(".post")
    parts = tuple(int(part) for part in main.split("."))
    post_key = int(post) if post else -1
    return (*parts, post_key)


def normalize_version(version):
    return version.strip().split("+", 1)[0]


def fetch_text(url):
    request = Request(url, headers={"User-Agent": "He-Forge-ComfyUI PyTorch tag updater"})
    with urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def parse_previous_versions(text, min_version):
    command_pattern = re.compile(
        r"pip install torch==(?P<torch>\d+\.\d+\.\d+)\s+"
        r"torchvision==(?P<torchvision>\d+\.\d+\.\d+)\s+"
        r"torchaudio==(?P<torchaudio>\d+\.\d+\.\d+)\s+"
        r"--index-url https://download\.pytorch\.org/whl/(?P<profile>cu\d+)"
    )
    versions = {}
    min_key = version_key(min_version)

    for match in command_pattern.finditer(text):
        torch_version = match.group("torch")
        if version_key(torch_version) < min_key:
            continue

        entry = versions.setdefault(
            torch_version,
            {
                "torchvision": match.group("torchvision"),
                "torchaudio": match.group("torchaudio"),
                "cuda_profiles": [],
            },
        )
        profile = match.group("profile")
        if profile not in entry["cuda_profiles"]:
            entry["cuda_profiles"].append(profile)

    return {
        version: versions[version]
        for version in sorted(versions.keys(), key=version_key, reverse=True)
    }


def torch_wheel_exists(profile, torch_version):
    index_url = f"https://download.pytorch.org/whl/{profile}/torch/"
    html = fetch_text(index_url)
    escaped_version = re.escape(torch_version)
    wheel_pattern = re.compile(rf"torch-{escaped_version}\+{re.escape(profile)}-", re.IGNORECASE)
    return bool(wheel_pattern.search(unescape(html)))


def xformers_wheel_exists(profile, xformers_version):
    index_url = f"https://download.pytorch.org/whl/{profile}/xformers/"
    html = fetch_text(index_url)
    escaped_version = re.escape(xformers_version)
    wheel_pattern = re.compile(rf"xformers-{escaped_version}-.*manylinux.*\.whl", re.IGNORECASE)
    return bool(wheel_pattern.search(unescape(html)))


def parse_torch_requirement(requirement):
    exact_match = re.search(r"torch\s*(?:\(|\s)*==\s*(?P<version>\d+\.\d+\.\d+)", requirement, re.IGNORECASE)
    if exact_match:
        return "exact", normalize_version(exact_match.group("version"))

    lower_match = re.search(r"torch\s*>=\s*(?P<version>\d+\.\d+(?:\.\d+)?)", requirement, re.IGNORECASE)
    if lower_match:
        version = normalize_version(lower_match.group("version"))
        if version.count(".") == 1:
            version = f"{version}.0"
        return "minimum", version

    return None, None


def fetch_xformers_versions(source_url):
    root = json.loads(fetch_text(source_url))
    metadata_base_url = source_url.rstrip("/")
    if metadata_base_url.endswith("/json"):
        metadata_base_url = metadata_base_url[: -len("/json")]

    release_versions = [
        version
        for version in root.get("releases", {})
        if re.match(r"^\d+\.\d+\.\d+(?:\.post\d+)?$", version)
    ]
    release_versions.sort(key=version_key, reverse=True)

    candidates = []
    for version in release_versions:
        metadata_url = f"{metadata_base_url}/{version}/json"
        metadata = json.loads(fetch_text(metadata_url))
        requirements = metadata.get("info", {}).get("requires_dist") or []
        torch_requirements = [item for item in requirements if item.lower().startswith("torch")]
        if not torch_requirements:
            continue

        requirement_type, torch_version = parse_torch_requirement(torch_requirements[0])
        if not requirement_type:
            continue

        candidates.append(
            {
                "version": version,
                "requirement": torch_requirements[0],
                "requirement_type": requirement_type,
                "torch_version": torch_version,
            }
        )

    return candidates


def attach_xformers_versions(versions, xformers_candidates):
    for torch_version, entry in versions.items():
        exact_candidates = [
            candidate
            for candidate in xformers_candidates
            if candidate["requirement_type"] == "exact" and candidate["torch_version"] == torch_version
        ]
        minimum_candidates = [
            candidate
            for candidate in xformers_candidates
            if candidate["requirement_type"] == "minimum" and version_key(torch_version) >= version_key(candidate["torch_version"])
        ]
        selected = exact_candidates[0] if exact_candidates else (minimum_candidates[0] if minimum_candidates else None)
        if selected:
            entry["xformers"] = {
                "version": selected["version"],
                "torch_requirement": selected["requirement"],
                "cuda_profiles": list(entry["cuda_profiles"]),
            }

    return versions


def filter_verified_wheels(versions):
    verified = {}
    for torch_version, entry in versions.items():
        profiles = []
        for profile in entry["cuda_profiles"]:
            if torch_wheel_exists(profile, torch_version):
                profiles.append(profile)

        if profiles:
            verified_entry = {
                "torchvision": entry["torchvision"],
                "torchaudio": entry["torchaudio"],
                "cuda_profiles": profiles,
            }
            if entry.get("xformers"):
                xformers_profiles = [
                    profile
                    for profile in profiles
                    if xformers_wheel_exists(profile, entry["xformers"]["version"])
                ]
                if xformers_profiles:
                    verified_entry["xformers"] = {
                        "version": entry["xformers"]["version"],
                        "torch_requirement": entry["xformers"]["torch_requirement"],
                        "cuda_profiles": xformers_profiles,
                    }

            verified[torch_version] = {
                **verified_entry,
            }

    return verified


def main():
    args = parse_args()
    script_dir = Path(__file__).resolve().parent
    docker_dir = script_dir.parent
    output_path = Path(args.output) if args.output else docker_dir / "data" / "pytorch-tags.json"

    previous_text = fetch_text(args.previous_url)
    versions = parse_previous_versions(previous_text, args.min_version)
    if not versions:
        raise RuntimeError("没有从 PyTorch previous-versions 页面解析到 pip CUDA wheel 版本矩阵")

    xformers_candidates = fetch_xformers_versions(args.xformers_url)
    versions = attach_xformers_versions(versions, xformers_candidates)

    if args.verify_wheels:
        versions = filter_verified_wheels(versions)
        if not versions:
            raise RuntimeError("wheel index 校验后没有保留任何 PyTorch CUDA wheel 版本")

    payload = {
        "source_urls": {
            "locally": args.locally_url,
            "previous_versions": args.previous_url,
            "wheel_index": "https://download.pytorch.org/whl/",
            "xformers": args.xformers_url,
        },
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "wheel_index_verified": args.verify_wheels,
        "versions": versions,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"PyTorch 版本数量：{len(versions)}")
    latest = next(iter(versions))
    print(f"最新：torch {latest}, CUDA 源：{', '.join(versions[latest]['cuda_profiles'])}")
    xformers_count = sum(1 for entry in versions.values() if entry.get("xformers"))
    print(f"xformers 匹配数量：{xformers_count}")
    print(f"已写入：{output_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"更新 PyTorch 版本矩阵失败：{exc}", file=sys.stderr)
        sys.exit(1)
