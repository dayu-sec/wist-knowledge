#!/usr/bin/env bash
# 把知识库打成可下载的**制品**：`wist-knowledge-<version>.tar.gz`
#
# 为什么打成包：网关侧按**制品**消费（形态对齐既有「Agent 安装包」——管理面录入 / 离线投放 /
# 版本历史 / 内容寻址），而不是让网关去读本仓的目录结构。包名与顶层目录名都带版本，
# 与安装包同一约定（`<名字>-<版本>`，见 wist-gateway `api/install_package.rs`）。
#
# 用法：
#   ./scripts/package.sh                        # 版本取自 version.txt
#   ./scripts/package.sh --version 0.1.0-alpha
#   ./scripts/package.sh --out dist
#   ./scripts/package.sh --dry-run              # 只打印会做什么，不落盘
#
# 产物：
#   <out>/wist-knowledge-<version>.tar.gz          顶层一层同名目录
#   <out>/wist-knowledge-<version>.tar.gz.sha256
#
# 真正的发布走 `.github/workflows/release.yml`（打 tag 触发，tag 名即版本）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/dist"
VERSION=""
DRY_RUN=0

# 包内容 = 五份策展数据（**白名单**，不是 `*`：目录里以后多出别的东西不该被顺手打进制品）。
KNOWLEDGE_FILES=(catalog.toml packs.toml templates.toml purpose-rules.toml aspect-policies.toml)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1（--help 看用法）" >&2; exit 2 ;;
  esac
done

# version.txt 是版本权威（`gx adm v_patch` / `v_feat` 改的就是它）。tag 与它不一致，
# 说明「先打了 tag、却忘了 bump」，这种漂移要在发布口拦住。
# version.txt 是版本权威（`gx adm v_patch` / `v_feat` 改的就是它）。制品 tag 在基版本上带通道后缀
# （`-alpha` / `-beta`，见 `_gal/vfm.gxl` 的 `tag_alpha` / `tag_beta`），所以合法形态就是
# `<基版本>` 或 `<基版本>-*`。对不上说明「先打了 tag、却忘了 bump」，这种漂移要在发布口拦住。
FILE_VERSION=""
if [[ -f "${ROOT}/version.txt" ]]; then
  FILE_VERSION="$(tr -d '[:space:]' < "${ROOT}/version.txt")"
fi
[[ -n "${VERSION}" ]] || VERSION="${FILE_VERSION}"
[[ -n "${VERSION}" ]] || { echo "版本为空：version.txt 缺失或为空，用 --version 指定" >&2; exit 2; }
if [[ -n "${FILE_VERSION}" ]]; then
  case "${VERSION}" in
    "${FILE_VERSION}" | "${FILE_VERSION}-"*) ;;
    *)
      echo "版本不一致：tag/参数是 ${VERSION}，version.txt 是 ${FILE_VERSION}" >&2
      echo "  合法形态：${FILE_VERSION} 或 ${FILE_VERSION}-alpha / -beta 这类通道后缀。" >&2
      echo "  先 bump version.txt（gx adm v_patch / v_feat），再打对应 tag。" >&2
      exit 2
      ;;
  esac
fi

for name in "${KNOWLEDGE_FILES[@]}"; do
  [[ -f "${ROOT}/${name}" ]] || { echo "缺文件：${ROOT}/${name}" >&2; exit 2; }
done

PACKAGE="wist-knowledge-${VERSION}"
TARBALL="${OUT}/${PACKAGE}.tar.gz"

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "[dry-run] 不去写盘。会做的事："
  echo "  版本        ${VERSION}（与 version.txt 一致）"
  echo "  顶层目录    ${PACKAGE}/"
  echo "  内容        ${KNOWLEDGE_FILES[*]} + manifest.json"
  echo "  产物        ${TARBALL}"
  echo "              ${TARBALL}.sha256"
  exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
DEST="${STAGE}/${PACKAGE}"
mkdir -p "${DEST}"
for name in "${KNOWLEDGE_FILES[@]}"; do
  cp "${ROOT}/${name}" "${DEST}/${name}"
done

# manifest.json：让包**自描述**（导入侧不必先解包就知道是哪一版、有没有被改过）。
# 只记录文件里**已经声明**的版本，不替它们发明版本号；`files` 在 manifest 自己写盘前算，
# 所以它列的是五份数据（manifest 自己不自我摘要）。
python3 - "${ROOT}" "${DEST}" "${VERSION}" <<'PY'
import hashlib, json, pathlib, re, subprocess, sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
version = sys.argv[3]


def read(name):
    return (dest / name).read_text(encoding="utf-8")


def top_level(text, key):
    """顶层 `key = <数字>`：取第一条（子条目里重名的靠前不算，见各文件头部的约定）。"""
    match = re.search(rf"(?m)^{key}\s*=\s*(\d+)\s*$", text)
    return int(match.group(1)) if match else None


def all_values(text, key):
    return sorted({int(value) for value in re.findall(rf"(?m)^{key}\s*=\s*(\d+)\s*$", text)})


content_versions = {}
catalog_version = top_level(read("catalog.toml"), "catalog_version")
if catalog_version is not None:
    content_versions["catalog_version"] = catalog_version
template_versions = all_values(read("templates.toml"), "template_version")
if template_versions:
    content_versions["template_version"] = template_versions
policy_version = top_level(read("aspect-policies.toml"), "policy_version")
if policy_version is not None:
    content_versions["policy_version"] = policy_version

try:
    commit = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
except Exception:
    commit = ""

files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(dest.iterdir())}

manifest = {
    "name": "wist-knowledge",
    "version": version,
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "commit": commit,
    "content_versions": content_versions,
    "files": files,
}
(dest / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(f"  manifest.json  content_versions={content_versions} commit={commit or '-'}")
PY

mkdir -p "${OUT}"
rm -f "${TARBALL}" "${TARBALL}.sha256"
# `-C STAGE` + 相对目录名：包内第一段就是 `<名字>-<版本>`（与安装包同一约定）。
tar -czf "${TARBALL}" -C "${STAGE}" "${PACKAGE}"
sha256_of "${TARBALL}" > "${TARBALL}.sha256.tmp"
printf '%s  %s\n' "$(cat "${TARBALL}.sha256.tmp")" "$(basename "${TARBALL}")" > "${TARBALL}.sha256"
rm -f "${TARBALL}.sha256.tmp"

echo "已打包 → ${TARBALL}"
echo "  顶层目录  ${PACKAGE}/"
echo "  条目数    $(tar -tzf "${TARBALL}" | wc -l | tr -d ' ')"
echo "  摘要      $(cat "${TARBALL}.sha256")"
