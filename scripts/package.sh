#!/usr/bin/env bash
# 把知识库打包成可下载的制品：`wist-knowledge-<version>.tar.gz`
#
# 为什么打成包：网关侧按**包**消费（形态对齐既有「Agent 安装包」——管理面录入 / 离线投放 /
# 版本历史 / 内容寻址），而不是让网关去读本仓的目录结构。包名与顶层目录名都带版本，
# 与安装包同一约定（`<名字>-<版本>`，见 wist-gateway `api/install_package.rs`）。
#
# 用法：
#   ./scripts/package.sh                        # 版本取自 version.txt
#   ./scripts/package.sh --version 0.1.1
#   ./scripts/package.sh --out dist
#   ./scripts/package.sh --allow-draft          # 允许 stable 包含 draft 单元（默认禁止）
#   ./scripts/package.sh --dry-run              # 只打印会做什么，不落盘
#
# 产物：
#   <out>/wist-knowledge-<version>.tar.gz          顶层一层同名目录
#   <out>/wist-knowledge-<version>.tar.gz.sha256
#   <out>/wist-knowledge-<version>.tar.gz.sig      仅在 KNOWLEDGE_SIGNING_KEY 给定时产出
#
# 本仓发布的是**制品**：分支 `alpha → beta → main`，tag 带通道后缀
#（`vX.Y.Z-alpha` / `vX.Y.Z-beta` / `vX.Y.Z`）。包名/版本带**同一条**后缀
#（`wist-knowledge-0.8.0-alpha.tar.gz`），但核心版本必须与 `version.txt` 一致。
#
# **成熟度（maturity）由通道自动推导，不允许手填**：
#   `-alpha` → `experimental` / `-beta` → `preview` / 无后缀 → `stable`
# 它写进 `manifest.json`，供没有 Git 上下文的消费方（网关）判断能不能装。
# 另两道闸门：`stable` 包**不得含 draft 单元**（要带就 `--allow-draft`）；
# `compat.json` 的 `version` 必须等于 `version.txt`。
# 真正的发布走 `.github/workflows/release.yml`（打 tag 触发）；本地用 `--dry-run` 预览。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/dist"
VERSION=""
DRY_RUN=0
ALLOW_DRAFT=0

# 包内容 = 五份策展数据（**白名单**，不是 `*`：目录里以后多出别的东西不该被顺手打进制品）。
KNOWLEDGE_FILES=(catalog.toml packs.toml templates.toml purpose-rules.toml aspect-policies.toml)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --allow-draft) ALLOW_DRAFT=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$1（--help 看用法）" >&2; exit 2 ;;
  esac
done

# version.txt 是**核心版本**的权威（`gx adm v_patch` / `v_feat` 改的就是它）。
# tag 可以带通道后缀（`-alpha` / `-beta`），但**核心版本**必须与它一致 ——
# 对不上说明「先打了 tag、却忘了 bump」，这种漂移要在发布口拦住。
FILE_VERSION=""
if [[ -f "${ROOT}/version.txt" ]]; then
  FILE_VERSION="$(tr -d '[:space:]' < "${ROOT}/version.txt")"
fi
[[ -n "${VERSION}" ]] || VERSION="${FILE_VERSION}"
[[ -n "${VERSION}" ]] || { echo "版本为空：version.txt 缺失或为空，用 --version 指定" >&2; exit 2; }

# 拆通道：`0.8.0-alpha` → core=0.8.0 / channel=alpha；`0.8.0` → core=0.8.0 / channel=（空）。
CORE_VERSION="${VERSION%%-*}"
CHANNEL=""
if [[ "${VERSION}" != "${CORE_VERSION}" ]]; then
  CHANNEL="${VERSION#*-}"
  case "${CHANNEL}" in
    alpha | beta) ;;
    *)
      echo "通道后缀只认 -alpha / -beta（收到：${VERSION}）" >&2
      exit 2
      ;;
  esac
fi

# 成熟度由通道推导（**不手填**）：它是给消费方看的「这份包能不能上生产」，
# 而不是内容就绪度（那是单元的 status）。
MATURITY="stable"
case "${CHANNEL}" in
  alpha) MATURITY="experimental" ;;
  beta) MATURITY="preview" ;;
esac

if [[ -n "${FILE_VERSION}" && "${CORE_VERSION}" != "${FILE_VERSION}" ]]; then
  echo "版本不一致：tag/参数的核心版本是 ${CORE_VERSION}，version.txt 是 ${FILE_VERSION}" >&2
  echo "  tag 可以是 v${FILE_VERSION}-alpha / -beta / v${FILE_VERSION}（通道后缀照带，核心版本要对上）。" >&2
  echo "  先 bump version.txt（gx adm v_patch / v_feat），再在对应分支上打 tag。" >&2
  exit 2
fi

for name in "${KNOWLEDGE_FILES[@]}"; do
  [[ -f "${ROOT}/${name}" ]] || { echo "缺文件：${ROOT}/${name}" >&2; exit 2; }
done

# `compat.json` 的 `version` 就是组件版本，不能与 `version.txt` 漂开 ——
# 漂开时网关会按错版本判兼容，而且没有任何地方会报错。
if [[ -f "${ROOT}/compat.json" ]]; then
  COMPAT_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8")).get("version", ""))' "${ROOT}/compat.json")"
  if [[ -n "${COMPAT_VERSION}" && "${COMPAT_VERSION}" != "${FILE_VERSION}" ]]; then
    echo "compat.json 的 version（${COMPAT_VERSION}）与 version.txt（${FILE_VERSION}）不一致" >&2
    echo "  bump 版本时两者要一起改；否则网关会按错误的组件版本判兼容。" >&2
    exit 2
  fi
fi

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
  echo "  版本        ${VERSION}（核心 ${CORE_VERSION} 与 version.txt 一致${CHANNEL:+，通道 ${CHANNEL}}）"
  echo "  成熟度      ${MATURITY}"
  echo "  顶层目录    ${PACKAGE}/"
  echo "  内容        ${KNOWLEDGE_FILES[*]} + manifest.json"
  echo "  产物        ${TARBALL}"
  echo "              ${TARBALL}.sha256"
  if [[ -n "${KNOWLEDGE_SIGNING_KEY:-}" ]]; then
    echo "              ${TARBALL}.sig（会用 ${KNOWLEDGE_SIGNING_KEY} 签）"
  else
    echo "  签名        无（KNOWLEDGE_SIGNING_KEY 未设置）"
  fi
  exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
DEST="${STAGE}/${PACKAGE}"
mkdir -p "${DEST}"
for name in "${KNOWLEDGE_FILES[@]}"; do
  cp "${ROOT}/${name}" "${DEST}/${name}"
done

# 可选的兼容性声明：网关录入/激活时会读它（`requires` / `supports` / `compat_mode`）。
# 没有它也能发包，只是网关按“兼容性未知”告警；有它才能在下发前拦住不兼容组合。
if [[ -f "${ROOT}/compat.json" ]]; then
  cp "${ROOT}/compat.json" "${DEST}/compat.json"
fi

# manifest.json：让包**自描述**（导入侧不必先解包就知道是哪一版、有没有被改过）。
# 只记录文件里**已经声明**的版本，不替它们发明版本号；`files` 在 manifest 自己写盘前算，
# 所以它列的是五份数据（manifest 自己不自我摘要）。
python3 - "${ROOT}" "${DEST}" "${VERSION}" "${MATURITY}" "${ALLOW_DRAFT}" <<'PY'
import hashlib, json, pathlib, re, subprocess, sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
dest = pathlib.Path(sys.argv[2])
version = sys.argv[3]
maturity = sys.argv[4]
allow_draft = sys.argv[5] == "1"


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
purpose_version = top_level(read("purpose-rules.toml"), "purpose_version")
if purpose_version is not None:
    content_versions["purpose_version"] = purpose_version

try:
    commit = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
except Exception:
    commit = ""

files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(dest.iterdir())}

# 内容就绪度：按单元 `status` 计数。它与包成熟度是两回事 —— 前者是「这个采法能不能派单」，
# 后者是「这份目录能不能上生产」。
catalog_text = read("catalog.toml")
unit_blocks = catalog_text.split("[[units]]")[1:]
counts = {"active": 0, "draft": 0, "deprecated": 0}
draft_units = []
for block in unit_blocks:
    status = re.search(r'(?m)^status\s*=\s*"([^"]+)"', block)
    state = status.group(1) if status else "active"
    counts[state] = counts.get(state, 0) + 1
    if state == "draft":
        unit_id = re.search(r'(?m)^unit_id\s*=\s*"([^"]+)"', block)
        draft_units.append(unit_id.group(1) if unit_id else "?")

# 成熟度闸门：「稳定版目录里带不可用单元」本身就是矛盾。要带 draft 发，
# 只能走 -alpha / -beta，或显式 --allow-draft（会写进 manifest 留痕）。
if maturity == "stable" and draft_units and not allow_draft:
    print(
        f"stable 包不得包含 draft 单元（共 {len(draft_units)} 个）：{', '.join(draft_units)}\n"
        "  要么把它们改 active，要么把包发成 -beta / -alpha，要么显式 --allow-draft（会留痕）。",
        file=sys.stderr,
    )
    sys.exit(2)

manifest = {
    "name": "wist-knowledge",
    "version": version,
    "maturity": maturity,
    "allow_draft": allow_draft,
    "created_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "commit": commit,
    "content_versions": content_versions,
    "counts": {
        "units": counts,
        "families": len(re.findall(r'(?m)^\[\[families\]\]', catalog_text)),
        "packs": len(re.findall(r'(?m)^\[\[pack\]\]', read("packs.toml"))),
        "templates": len(re.findall(r'(?m)^\[\[template\]\]', read("templates.toml"))),
    },
    "files": files,
}
(dest / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print(f"  manifest.json  content_versions={content_versions} commit={commit or '-'}")
print(
    f"  成熟度      {maturity}（units: "
    f"active={counts['active']} draft={counts['draft']} deprecated={counts['deprecated']}）"
)
PY

mkdir -p "${OUT}"
rm -f "${TARBALL}" "${TARBALL}.sha256" "${TARBALL}.sig"
# `-C STAGE` + 相对目录名：包内第一段就是 `<名字>-<版本>`（与安装包同一约定）。
tar -czf "${TARBALL}" -C "${STAGE}" "${PACKAGE}"
SHA="$(sha256_of "${TARBALL}")"
printf '%s  %s\n' "${SHA}" "$(basename "${TARBALL}")" > "${TARBALL}.sha256"

# 签名（设计 §9）：一把 Ed25519 私钥，签的是**摘要的十六进制文本**（与 `.sha256` 里那串同一段
# 字节）——运维拿 openssl 能手工重验。私钥只放 CI secret（`KNOWLEDGE_SIGNING_KEY`），不进仓、
# 不进网关；网关侧只配公钥。与安装脚本那把签名同一简单度：不做多密钥共存。
if [[ -n "${KNOWLEDGE_SIGNING_KEY:-}" ]]; then
  msg="$(mktemp)"
  sig="$(mktemp)"
  printf '%s' "${SHA}" > "${msg}"
  if ! openssl pkeyutl -sign -rawin -inkey "${KNOWLEDGE_SIGNING_KEY}" -in "${msg}" -out "${sig}" >/dev/null 2>&1; then
    rm -f "${msg}" "${sig}"
    echo "签名失败：需要 OpenSSL ≥ 3.0 做 Ed25519 原始签名（本机：$(openssl version 2>/dev/null || echo 未找到 openssl)）。" >&2
    echo "  发布请走 CI（.github/workflows/release.yml 用 secret 签）；本地要签请装真 openssl。" >&2
    exit 1
  fi
  base64 < "${sig}" | tr -d '\n' > "${TARBALL}.sig"
  printf '\n' >> "${TARBALL}.sig"
  rm -f "${msg}" "${sig}"
  echo "  签名      $(basename "${TARBALL}").sig（Ed25519，签的就是上面那串 sha256）"
else
  echo "  签名      无（KNOWLEDGE_SIGNING_KEY 未设置）"
  echo "            → 配了验签公钥的网关会拒收这份包；正式发布请走 CI（secret 已配）"
fi

echo "已打包 → ${TARBALL}"
echo "  顶层目录  ${PACKAGE}/"
echo "  条目数    $(tar -tzf "${TARBALL}" | wc -l | tr -d ' ')"
echo "  摘要      $(cat "${TARBALL}.sha256")"
