#!/usr/bin/env python3
"""校验「内容变了，版本必须跟着涨」。

用法：
    check_content_versions.py <上一版 manifest.json> <本版 manifest.json> [上一版 tag] [本版 tag]

规则：五份策展数据里任何一份的 sha256 变了，它对应的版本号必须**严格变大**：

    catalog.toml          → catalog_version
    packs.toml            → catalog_version   （包自身没有独立版本，随目录走）
    templates.toml        → template_version  （取最大值）
    purpose-rules.toml    → purpose_version
    aspect-policies.toml  → policy_version

为什么需要：包能打出来、网关也能装，所以漂移不会被任何一步挡住；但下游按
`catalog_version` 判新旧、判回滚、锁 `StandingWork`，版本不动等于**两份不同内容
共用一个版本号** —— 回滚会回错东西。

退出码：0 = 通过（含「无变化」），1 = 违反单调性，2 = 用法/读取错误。
上一版缺 `files`（旧包）时只告警，不判失败 —— 老包没有逐文件摘要，无从比较。
"""

from __future__ import annotations

import json
import sys

# 文件 → 它应当驱动的版本键。一个版本键可能由多个文件驱动（catalog.toml 与 packs.toml
# 都随 catalog_version 走），只要任一文件变了就必须涨。
FILE_TO_KEY = {
    "catalog.toml": "catalog_version",
    "packs.toml": "catalog_version",
    "templates.toml": "template_version",
    "purpose-rules.toml": "purpose_version",
    "aspect-policies.toml": "policy_version",
}


def load(path: str) -> dict:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"读取 manifest 失败：{path}（{exc}）", file=sys.stderr)
        raise SystemExit(2)


def version_of(manifest: dict, key: str):
    """`content_versions` 里的值可能是 int，也可能是 int 列表（templates 逐个版本）。

    列表取最大值 —— 只要「最新的那个模板」涨了就算涨；这能挡住「改了模板却没动版本」，
    同时允许新增一个 version = 1 的模板而不必把老模板都推一遍。
    """
    value = manifest.get("content_versions", {}).get(key)
    if isinstance(value, list):
        return max(value) if value else None
    return value


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2

    prev_path, new_path = argv[1], argv[2]
    prev_tag = argv[3] if len(argv) > 3 else "上一版"
    new_tag = argv[4] if len(argv) > 4 else "本版"

    prev, new = load(prev_path), load(new_path)
    prev_files, new_files = prev.get("files") or {}, new.get("files") or {}
    if not prev_files:
        print(
            f"::warning::{prev_tag} 的 manifest 没有逐文件摘要（旧包），跳过单调性校验"
        )
        return 0

    problems: list[str] = []
    rows: list[tuple[str, str, str, str, str]] = []

    for name, key in FILE_TO_KEY.items():
        if name not in prev_files or name not in new_files:
            continue
        changed = prev_files[name] != new_files[name]
        # 同一版本键可能被多个文件驱动，取「哪个文件变了」的并集判断，见下面的 per-key 汇总。
        rows.append(
            (
                name,
                key,
                str(version_of(prev, key)),
                str(version_of(new, key)),
                "变了" if changed else "未变",
            )
        )

    # 版本倒退总是错（哪怕文件没变）—— 回滚会回到更旧的目录。
    for key in sorted({row[1] for row in rows}):
        old, new_v = version_of(prev, key), version_of(new, key)
        if old is not None and new_v is not None and new_v < old:
            problems.append(f"{key} 倒退了（{old} → {new_v}）")

    # 按版本键汇总：该键下任一文件变了，就必须严格变大。
    changed_keys: dict[str, list[str]] = {}
    for name, key, _old, _new, state in rows:
        if state == "变了":
            changed_keys.setdefault(key, []).append(name)

    for key, files in sorted(changed_keys.items()):
        old, new_v = version_of(prev, key), version_of(new, key)
        if old is None or new_v is None:
            problems.append(f"{key}：缺版本号（{prev_tag}={old}，{new_tag}={new_v}）")
            continue
        if new_v <= old:
            problems.append(
                f"{key} 没有涨（{old} → {new_v}），但 {'、'.join(sorted(files))} 变了"
            )

    width = max((len(row[0]) for row in rows), default=10)
    print(f"{'文件'.ljust(width)}  {'版本键':<20} {prev_tag:>12}  {new_tag:>12}  变化")
    for name, key, old, new_v, state in rows:
        print(f"{name.ljust(width)}  {key:<20} {old:>12}  {new_v:>12}  {state}")

    if problems:
        print("", file=sys.stderr)
        for problem in problems:
            print(f"::error::内容版本漂移：{problem}", file=sys.stderr)
        print(
            "  改了内容就必须升对应版本（catalog 19→20 之类），否则回滚会回错东西。",
            file=sys.stderr,
        )
        return 1

    print("内容版本单调性通过。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
