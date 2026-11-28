#!/usr/bin/env python3
"""校验「内容变了，版本必须跟着涨」。

用法：
    check_content_versions.py <上一版 manifest.json> <本版 manifest.json> [上一版 tag] [本版 tag]

规则：目录里任何一份**策展数据**的 sha256 变了，它对应的版本号必须**严格变大**：

    catalog.toml          → catalog_version
    packs.toml            → catalog_version   （包自身没有独立版本，随目录走）
    templates.toml        → template_version  （取最大值）
    purpose-rules.toml    → purpose_version
    aspect-policies.toml  → policy_version
    exporters.toml        → exporters_version

另外：manifest 里出现了**没登记版本键**的文件时直接判失败（退出码 1）。
没登记就等于给这个文件留了「改了不用涨版本」的永久免检通道 ——
这正是版本漂移最常见的入口，比单调性本身更该先挡住。

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
    # 导出器运行参数（二进制搜索目录 / 周期 / 超时）：只影响“去哪找工具、多久跑一次”，
    # 但同样是舰队级内容 —— 改了不涨版本，回滚就会回错东西。
    "exporters.toml": "exporters_version",
}

# 包里有、但**不由内容版本键管**的文件：
#
#   * `manifest.json` —— 包自身的摘要（生成时 `files` 里还没有它，但历史手工包可能有）；
#   * `compat.json` —— 组件版本 + 依赖区间，它的 `version` 必须等于 `version.txt`，
#     由 `package.sh` 单独校验（与内容版本是两套轴）。
#
# 它俩被扫进来时不能判成“漏登记”：它们本来就不靠 `catalog_version` / `template_version` 这类键。
NO_CONTENT_VERSION_FILES = {"manifest.json", "compat.json"}


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

    # 先查「这一版有没有文件没登记版本键」。它比单调性更基础：没登记的文件
    # 根本进不了下面的逐项比较，等于被永久免检。
    #
    # 只查**本版**：上一版的历史缺口不该让今天的发版回溯失败 —— 缺口在
    # 下一次打包时自然会被这里挡住。
    unmapped = sorted(
        name
        for name in new_files
        if name not in FILE_TO_KEY and name not in NO_CONTENT_VERSION_FILES
    )
    if unmapped:
        print(
            "::error::以下策展文件没有登记版本键，无法判定「内容变了版本要涨」："
            + "、".join(unmapped),
            file=sys.stderr,
        )
        print(
            "  在 check_content_versions.py 的 FILE_TO_KEY 里登记（文件 → 版本键），"
            "并在该文件里声明对应版本号；确实不需要版本的产物请显式说明。",
            file=sys.stderr,
        )
        return 1

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
